package main

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

const maxBodyBytes = 64 << 10

type config struct {
	ListenAddr      string
	PublicURL       string
	AppCallbackURL  string
	ClientID        string
	ClientSecret    string
	AuthBaseURL     string
	FleetBaseURL    string
	CommandProxyURL string
	CommandProxyCA  string
	Scopes          string
	StorePath       string
	MasterKey       []byte
	SessionLifetime time.Duration
	RequestTimeout  time.Duration
}

func loadConfig() (config, error) {
	c := config{
		ListenAddr:      env("LISTEN_ADDR", ":8080"),
		PublicURL:       strings.TrimRight(env("PUBLIC_URL", "https://api.txx.app"), "/"),
		AppCallbackURL:  env("APP_CALLBACK_URL", "teslablekey://oauth/callback"),
		ClientID:        os.Getenv("TESLA_CLIENT_ID"),
		ClientSecret:    os.Getenv("TESLA_CLIENT_SECRET"),
		AuthBaseURL:     strings.TrimRight(env("TESLA_AUTH_BASE_URL", "https://auth.tesla.cn/oauth2/v3"), "/"),
		FleetBaseURL:    strings.TrimRight(env("TESLA_FLEET_BASE_URL", "https://fleet-api.prd.cn.vn.cloud.tesla.cn"), "/"),
		CommandProxyURL: strings.TrimRight(env("TESLA_COMMAND_PROXY_URL", "https://vehicle-command:4443"), "/"),
		CommandProxyCA:  env("TESLA_COMMAND_PROXY_CA", "/secrets/proxy-ca.pem"),
		Scopes:          env("TESLA_SCOPES", "openid offline_access user_data vehicle_device_data vehicle_cmds vehicle_charging_cmds"),
		StorePath:       env("STORE_PATH", "/data/store.json"),
		SessionLifetime: 90 * 24 * time.Hour,
		RequestTimeout:  30 * time.Second,
	}
	keyText := os.Getenv("TOKEN_ENCRYPTION_KEY")
	if keyText != "" {
		key, err := base64.StdEncoding.DecodeString(keyText)
		if err != nil || len(key) != 32 {
			return config{}, errors.New("TOKEN_ENCRYPTION_KEY must be base64 for exactly 32 bytes")
		}
		c.MasterKey = key
	}
	callback, err := url.Parse(c.AppCallbackURL)
	if err != nil || callback.Scheme == "" {
		return config{}, errors.New("APP_CALLBACK_URL must be an absolute URL")
	}
	return c, nil
}

func env(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

type oauthState struct {
	ExpiresAt time.Time `json:"expires_at"`
	Nonce     string    `json:"nonce"`
}

type exchangeCode struct {
	SessionToken string    `json:"session_token"`
	ExpiresAt    time.Time `json:"expires_at"`
}

type session struct {
	ID                string    `json:"id"`
	TokenHash         string    `json:"token_hash"`
	TeslaAccessToken  string    `json:"tesla_access_token"`
	TeslaRefreshToken string    `json:"tesla_refresh_token"`
	TeslaExpiresAt    time.Time `json:"tesla_expires_at"`
	Scopes            string    `json:"scopes"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
	ExpiresAt         time.Time `json:"expires_at"`
}

type storeData struct {
	States    map[string]oauthState   `json:"states"`
	Exchanges map[string]exchangeCode `json:"exchanges"`
	Sessions  map[string]session      `json:"sessions"`
}

type store struct {
	mu   sync.Mutex
	path string
	data storeData
}

func openStore(path string) (*store, error) {
	s := &store{path: path, data: storeData{States: map[string]oauthState{}, Exchanges: map[string]exchangeCode{}, Sessions: map[string]session{}}}
	contents, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(contents, &s.data); err != nil {
		return nil, fmt.Errorf("decode store: %w", err)
	}
	if s.data.States == nil {
		s.data.States = map[string]oauthState{}
	}
	if s.data.Exchanges == nil {
		s.data.Exchanges = map[string]exchangeCode{}
	}
	if s.data.Sessions == nil {
		s.data.Sessions = map[string]session{}
	}
	return s, nil
}

func (s *store) update(fn func(*storeData) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	for k, v := range s.data.States {
		if now.After(v.ExpiresAt) {
			delete(s.data.States, k)
		}
	}
	for k, v := range s.data.Exchanges {
		if now.After(v.ExpiresAt) {
			delete(s.data.Exchanges, k)
		}
	}
	for k, v := range s.data.Sessions {
		if now.After(v.ExpiresAt) {
			delete(s.data.Sessions, k)
		}
	}
	if err := fn(&s.data); err != nil {
		return err
	}
	return s.saveLocked()
}

func (s *store) readSession(token string) (session, bool) {
	hash := tokenHash(token)
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, candidate := range s.data.Sessions {
		if subtle.ConstantTimeCompare([]byte(candidate.TokenHash), []byte(hash)) == 1 && time.Now().Before(candidate.ExpiresAt) {
			return candidate, true
		}
	}
	return session{}, false
}

func (s *store) saveLocked() error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0700); err != nil {
		return err
	}
	b, err := json.Marshal(s.data)
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, b, 0600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

type server struct {
	cfg       config
	store     *store
	aead      cipher.AEAD
	http      *http.Client
	proxyHTTP *http.Client
	logger    *slog.Logger
}

func newServer(c config, s *store) (*server, error) {
	var aead cipher.AEAD
	if len(c.MasterKey) == 32 {
		block, err := aes.NewCipher(c.MasterKey)
		if err != nil {
			return nil, err
		}
		aead, err = cipher.NewGCM(block)
		if err != nil {
			return nil, err
		}
	}
	client := &http.Client{Timeout: c.RequestTimeout}
	proxyClient := client
	if certificate, err := os.ReadFile(c.CommandProxyCA); err == nil {
		roots := x509.NewCertPool()
		if !roots.AppendCertsFromPEM(certificate) {
			return nil, errors.New("TESLA_COMMAND_PROXY_CA does not contain a valid certificate")
		}
		proxyClient = &http.Client{
			Timeout: c.RequestTimeout,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{
				MinVersion: tls.VersionTLS12,
				RootCAs:    roots,
			}},
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("read command proxy CA: %w", err)
	}
	return &server{cfg: c, store: s, aead: aead, http: client, proxyHTTP: proxyClient, logger: slog.New(slog.NewJSONHandler(os.Stdout, nil))}, nil
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("GET /v1/config", s.publicConfig)
	mux.HandleFunc("POST /v1/auth/start", s.authStart)
	mux.HandleFunc("GET /oauth/callback", s.oauthCallback)
	mux.HandleFunc("GET /oauth/complete", s.oauthComplete)
	mux.HandleFunc("POST /v1/auth/exchange", s.authExchange)
	mux.HandleFunc("DELETE /v1/auth/session", s.requireSession(s.logout))
	mux.HandleFunc("GET /v1/vehicles", s.requireSession(s.listVehicles))
	mux.HandleFunc("GET /v1/vehicles/{vehicle}/data", s.requireSession(s.vehicleData))
	mux.HandleFunc("POST /v1/vehicles/{vehicle}/wake", s.requireSession(s.wakeVehicle))
	mux.HandleFunc("POST /v1/vehicles/{vehicle}/commands/{command}", s.requireSession(s.vehicleCommand))
	return securityHeaders(requestLog(s.logger, mux))
}

func (s *server) oauthComplete(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>小特蓝牙钥匙</title><body><main><h1>操作已完成</h1><p>现在可以返回小特蓝牙钥匙。</p></main></body></html>`)
}

func (s *server) configured() bool {
	return s.cfg.ClientID != "" && s.cfg.ClientSecret != "" && s.aead != nil
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "service": "tesla-backend", "oauth_configured": s.configured()})
}

func (s *server) publicConfig(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"oauth_configured": s.configured(),
		"region":           "china",
		"fleet_api":        s.cfg.FleetBaseURL,
		"virtual_key_url":  "https://tesla.cn/_ak/api.txx.app",
	})
}

func (s *server) authStart(w http.ResponseWriter, _ *http.Request) {
	if !s.configured() {
		problem(w, http.StatusServiceUnavailable, "oauth_not_configured", "Tesla developer credentials are not configured")
		return
	}
	state, _ := randomToken(32)
	nonce, _ := randomToken(32)
	if err := s.store.update(func(d *storeData) error {
		d.States[state] = oauthState{ExpiresAt: time.Now().Add(10 * time.Minute), Nonce: nonce}
		return nil
	}); err != nil {
		problem(w, 500, "store_error", "Could not create authorization request")
		return
	}
	q := url.Values{
		"response_type": {"code"}, "client_id": {s.cfg.ClientID},
		"redirect_uri": {s.cfg.PublicURL + "/oauth/callback"}, "scope": {s.cfg.Scopes},
		"state": {state}, "nonce": {nonce}, "prompt_missing_scopes": {"true"}, "require_requested_scopes": {"true"},
	}
	writeJSON(w, http.StatusOK, map[string]string{"authorization_url": s.cfg.AuthBaseURL + "/authorize?" + q.Encode()})
}

func (s *server) oauthCallback(w http.ResponseWriter, r *http.Request) {
	if oauthErr := r.URL.Query().Get("error"); oauthErr != "" {
		s.redirectApp(w, r, "", oauthErr)
		return
	}
	stateValue, code := r.URL.Query().Get("state"), r.URL.Query().Get("code")
	valid := false
	_ = s.store.update(func(d *storeData) error {
		st, ok := d.States[stateValue]
		if ok && time.Now().Before(st.ExpiresAt) && code != "" {
			valid = true
		}
		delete(d.States, stateValue)
		return nil
	})
	if !valid {
		problem(w, http.StatusBadRequest, "invalid_state", "Authorization request is invalid or expired")
		return
	}
	tokens, err := s.exchangeTeslaCode(r.Context(), code)
	if err != nil {
		s.logger.Error("oauth code exchange failed", "error", err)
		s.redirectApp(w, r, "", "token_exchange_failed")
		return
	}
	appToken, _ := randomToken(32)
	sessionID, _ := randomToken(16)
	oneTimeCode, _ := randomToken(32)
	access, err := s.encrypt(tokens.AccessToken)
	if err != nil {
		problem(w, 500, "encryption_error", "Token encryption failed")
		return
	}
	refresh, err := s.encrypt(tokens.RefreshToken)
	if err != nil {
		problem(w, 500, "encryption_error", "Token encryption failed")
		return
	}
	now := time.Now()
	entry := session{ID: sessionID, TokenHash: tokenHash(appToken), TeslaAccessToken: access, TeslaRefreshToken: refresh, TeslaExpiresAt: now.Add(time.Duration(tokens.ExpiresIn) * time.Second), Scopes: tokens.Scope, CreatedAt: now, UpdatedAt: now, ExpiresAt: now.Add(s.cfg.SessionLifetime)}
	if err := s.store.update(func(d *storeData) error {
		d.Sessions[sessionID] = entry
		d.Exchanges[oneTimeCode] = exchangeCode{SessionToken: appToken, ExpiresAt: now.Add(2 * time.Minute)}
		return nil
	}); err != nil {
		problem(w, 500, "store_error", "Could not persist login")
		return
	}
	s.redirectApp(w, r, oneTimeCode, "")
}

func (s *server) redirectApp(w http.ResponseWriter, r *http.Request, code, errorCode string) {
	target, _ := url.Parse(s.cfg.AppCallbackURL)
	q := target.Query()
	if code != "" {
		q.Set("code", code)
	}
	if errorCode != "" {
		q.Set("error", errorCode)
	}
	target.RawQuery = q.Encode()
	http.Redirect(w, r, target.String(), http.StatusFound)
}

func (s *server) authExchange(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Code string `json:"code"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	var token string
	found := false
	_ = s.store.update(func(d *storeData) error {
		if item, ok := d.Exchanges[body.Code]; ok && time.Now().Before(item.ExpiresAt) {
			token, found = item.SessionToken, true
		}
		delete(d.Exchanges, body.Code)
		return nil
	})
	if !found {
		problem(w, http.StatusUnauthorized, "invalid_exchange_code", "Login code is invalid or expired")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"access_token": token, "token_type": "Bearer", "expires_in": int64(s.cfg.SessionLifetime.Seconds())})
}

type teslaTokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
	Scope        string `json:"scope"`
	TokenType    string `json:"token_type"`
}

func (s *server) exchangeTeslaCode(ctx context.Context, code string) (teslaTokenResponse, error) {
	form := url.Values{"grant_type": {"authorization_code"}, "client_id": {s.cfg.ClientID}, "client_secret": {s.cfg.ClientSecret}, "code": {code}, "audience": {s.cfg.FleetBaseURL}, "redirect_uri": {s.cfg.PublicURL + "/oauth/callback"}, "scope": {s.cfg.Scopes}}
	return s.tokenRequest(ctx, form)
}

func (s *server) refreshTeslaToken(ctx context.Context, encryptedRefresh string) (teslaTokenResponse, error) {
	refresh, err := s.decrypt(encryptedRefresh)
	if err != nil {
		return teslaTokenResponse{}, err
	}
	form := url.Values{"grant_type": {"refresh_token"}, "client_id": {s.cfg.ClientID}, "refresh_token": {refresh}}
	return s.tokenRequest(ctx, form)
}

func (s *server) tokenRequest(ctx context.Context, form url.Values) (teslaTokenResponse, error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, s.cfg.AuthBaseURL+"/token", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := s.http.Do(req)
	if err != nil {
		return teslaTokenResponse{}, err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode/100 != 2 {
		return teslaTokenResponse{}, fmt.Errorf("token endpoint returned %d: %s", resp.StatusCode, redactBody(b))
	}
	var result teslaTokenResponse
	if err := json.Unmarshal(b, &result); err != nil {
		return result, err
	}
	if result.AccessToken == "" || result.RefreshToken == "" || result.ExpiresIn <= 0 {
		return result, errors.New("token endpoint returned incomplete token set")
	}
	return result, nil
}

type contextKey string

const sessionKey contextKey = "session"

func (s *server) requireSession(next func(http.ResponseWriter, *http.Request, session)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			problem(w, 401, "unauthorized", "Bearer session token is required")
			return
		}
		entry, ok := s.store.readSession(strings.TrimSpace(strings.TrimPrefix(header, "Bearer ")))
		if !ok {
			problem(w, 401, "invalid_session", "Session is invalid or expired")
			return
		}
		if time.Until(entry.TeslaExpiresAt) < 2*time.Minute {
			updated, err := s.refreshSession(r.Context(), entry)
			if err != nil {
				s.logger.Error("Tesla token refresh failed", "session", entry.ID, "error", err)
				problem(w, 401, "tesla_session_expired", "Tesla authorization must be renewed")
				return
			}
			entry = updated
		}
		next(w, r.WithContext(context.WithValue(r.Context(), sessionKey, entry)), entry)
	}
}

func (s *server) refreshSession(ctx context.Context, entry session) (session, error) {
	tokens, err := s.refreshTeslaToken(ctx, entry.TeslaRefreshToken)
	if err != nil {
		return entry, err
	}
	access, err := s.encrypt(tokens.AccessToken)
	if err != nil {
		return entry, err
	}
	refresh, err := s.encrypt(tokens.RefreshToken)
	if err != nil {
		return entry, err
	}
	entry.TeslaAccessToken, entry.TeslaRefreshToken = access, refresh
	entry.TeslaExpiresAt, entry.UpdatedAt, entry.Scopes = time.Now().Add(time.Duration(tokens.ExpiresIn)*time.Second), time.Now(), tokens.Scope
	err = s.store.update(func(d *storeData) error { d.Sessions[entry.ID] = entry; return nil })
	return entry, err
}

func (s *server) logout(w http.ResponseWriter, _ *http.Request, entry session) {
	_ = s.store.update(func(d *storeData) error { delete(d.Sessions, entry.ID); return nil })
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) listVehicles(w http.ResponseWriter, r *http.Request, entry session) {
	s.fleet(w, r, entry, http.MethodGet, "/api/1/vehicles", nil, false)
}
func (s *server) vehicleData(w http.ResponseWriter, r *http.Request, entry session) {
	id := r.PathValue("vehicle")
	if !validVehicleID(id) {
		problem(w, 400, "invalid_vehicle", "Vehicle identifier is invalid")
		return
	}
	s.fleet(w, r, entry, http.MethodGet, "/api/1/vehicles/"+url.PathEscape(id)+"/vehicle_data", nil, false)
}
func (s *server) wakeVehicle(w http.ResponseWriter, r *http.Request, entry session) {
	id := r.PathValue("vehicle")
	if !validVehicleID(id) {
		problem(w, 400, "invalid_vehicle", "Vehicle identifier is invalid")
		return
	}
	s.fleet(w, r, entry, http.MethodPost, "/api/1/vehicles/"+url.PathEscape(id)+"/wake_up", bytes.NewReader([]byte("{}")), false)
}

var allowedCommands = map[string]bool{
	"door_lock": true, "door_unlock": true, "flash_lights": true, "honk_horn": true,
	"actuate_trunk": true, "auto_conditioning_start": true, "auto_conditioning_stop": true,
	"charge_start": true, "charge_stop": true, "charge_port_door_open": true, "charge_port_door_close": true,
	"set_charge_limit": true, "set_temps": true, "set_sentry_mode": true, "remote_start_drive": true,
	"media_toggle_playback": true, "media_next_track": true, "media_prev_track": true,
	"window_control": true, "add_charge_schedule": true, "remove_charge_schedule": true,
	"add_precondition_schedule": true, "remove_precondition_schedule": true,
}

func (s *server) vehicleCommand(w http.ResponseWriter, r *http.Request, entry session) {
	vin, command := strings.ToUpper(r.PathValue("vehicle")), r.PathValue("command")
	if !regexp.MustCompile(`^[A-HJ-NPR-Z0-9]{17}$`).MatchString(vin) {
		problem(w, 400, "invalid_vin", "Commands require a valid 17-character VIN")
		return
	}
	if !allowedCommands[command] {
		problem(w, 404, "unsupported_command", "Command is not enabled by this service")
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		problem(w, 413, "body_too_large", "Command body is too large")
		return
	}
	if len(bytes.TrimSpace(body)) == 0 {
		body = []byte("{}")
	}
	if !json.Valid(body) {
		problem(w, 400, "invalid_json", "Command body must be JSON")
		return
	}
	s.fleet(w, r, entry, http.MethodPost, "/api/1/vehicles/"+vin+"/command/"+command, bytes.NewReader(body), true)
}

func (s *server) fleet(w http.ResponseWriter, r *http.Request, entry session, method, path string, body io.Reader, command bool) {
	token, err := s.decrypt(entry.TeslaAccessToken)
	if err != nil {
		problem(w, 500, "token_error", "Stored authorization could not be read")
		return
	}
	base := s.cfg.FleetBaseURL
	client := s.http
	if command {
		base, client = s.cfg.CommandProxyURL, s.proxyHTTP
	}
	req, err := http.NewRequestWithContext(r.Context(), method, base+path, body)
	if err != nil {
		problem(w, 500, "request_error", "Could not build Fleet API request")
		return
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "TeslaBLEKey/3.0")
	resp, err := client.Do(req)
	if err != nil {
		s.logger.Error("Fleet API request failed", "command", command, "error", err)
		problem(w, 502, "fleet_unavailable", "Tesla Fleet API is unavailable")
		return
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(resp.StatusCode)
	_, _ = w.Write(b)
}

var vehicleIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,32}$`)

func validVehicleID(id string) bool { return vehicleIDPattern.MatchString(id) }

func (s *server) encrypt(plain string) (string, error) {
	if s.aead == nil {
		return "", errors.New("encryption unavailable")
	}
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", err
	}
	sealed := s.aead.Seal(nonce, nonce, []byte(plain), nil)
	return base64.RawURLEncoding.EncodeToString(sealed), nil
}

func (s *server) decrypt(encoded string) (string, error) {
	b, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return "", err
	}
	if s.aead == nil || len(b) < s.aead.NonceSize() {
		return "", errors.New("invalid encrypted token")
	}
	plain, err := s.aead.Open(nil, b[:s.aead.NonceSize()], b[s.aead.NonceSize():], nil)
	return string(plain), err
}

func randomToken(size int) (string, error) {
	b := make([]byte, size)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(target); err != nil {
		problem(w, 400, "invalid_json", "Request body is invalid")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func problem(w http.ResponseWriter, status int, code, detail string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": detail}})
}
func redactBody(b []byte) string {
	if len(b) > 256 {
		b = b[:256]
	}
	return strings.ReplaceAll(string(b), "access_token", "redacted_token")
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		next.ServeHTTP(w, r)
	})
}
func requestLog(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		logger.Info("request", "method", r.Method, "path", r.URL.Path, "duration_ms", time.Since(start).Milliseconds())
	})
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		panic(err)
	}
	st, err := openStore(cfg.StorePath)
	if err != nil {
		panic(err)
	}
	srv, err := newServer(cfg, st)
	if err != nil {
		panic(err)
	}
	httpServer := &http.Server{Addr: cfg.ListenAddr, Handler: srv.routes(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 60 * time.Second, IdleTimeout: 90 * time.Second, MaxHeaderBytes: 32 << 10}
	srv.logger.Info("server starting", "address", cfg.ListenAddr, "oauth_configured", srv.configured())
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		panic(err)
	}
}
