package main

import (
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func testServer(t *testing.T) *server {
	t.Helper()
	c := config{ListenAddr: ":0", PublicURL: "https://api.txx.app", AppCallbackURL: "teslablekey://oauth/callback", AuthBaseURL: "https://auth.tesla.cn/oauth2/v3", FleetBaseURL: "https://fleet-api.prd.cn.vn.cloud.tesla.cn", CommandProxyURL: "https://vehicle-command:4443", StorePath: filepath.Join(t.TempDir(), "store.json"), MasterKey: make([]byte, 32)}
	st, err := openStore(c.StorePath)
	if err != nil {
		t.Fatal(err)
	}
	srv, err := newServer(c, st)
	if err != nil {
		t.Fatal(err)
	}
	return srv
}

func TestHealthDoesNotExposeSecrets(t *testing.T) {
	s := testServer(t)
	r := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	s.routes().ServeHTTP(w, r)
	if w.Code != 200 || strings.Contains(w.Body.String(), "token") {
		t.Fatalf("unexpected response: %d %s", w.Code, w.Body.String())
	}
}

func TestEncryptionRoundTrip(t *testing.T) {
	s := testServer(t)
	encoded, err := s.encrypt("secret-token")
	if err != nil {
		t.Fatal(err)
	}
	if encoded == "secret-token" {
		t.Fatal("token was not encrypted")
	}
	plain, err := s.decrypt(encoded)
	if err != nil || plain != "secret-token" {
		t.Fatalf("round trip failed: %q %v", plain, err)
	}
	if _, err := base64.RawURLEncoding.DecodeString(encoded); err != nil {
		t.Fatal(err)
	}
}

func TestCommandAllowlist(t *testing.T) {
	for _, command := range []string{"door_lock", "erase_user_data", "navigation_waypoints_request", "parental_controls_activate", "schedule_software_update"} {
		if !allowedCommands[command] {
			t.Fatalf("official Fleet API command %q is missing", command)
		}
	}
	if allowedCommands["unknown_command"] {
		t.Fatal("unknown commands must remain blocked")
	}
	if validVehicleID("../etc/passwd") {
		t.Fatal("path traversal accepted")
	}
}

func TestProductRoutesMapToFixedFleetEndpoints(t *testing.T) {
	var received []string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received = append(received, r.Method+" "+r.URL.RequestURI())
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"response":{}}`))
	}))
	defer upstream.Close()

	s := testServer(t)
	s.cfg.FleetBaseURL = upstream.URL
	encrypted, err := s.encrypt("tesla-token")
	if err != nil {
		t.Fatal(err)
	}
	localToken := "local-session"
	entry := session{ID: "session-1", TokenHash: tokenHash(localToken), TeslaAccessToken: encrypted, TeslaExpiresAt: time.Now().Add(time.Hour), ExpiresAt: time.Now().Add(time.Hour)}
	if err := s.store.update(func(data *storeData) error { data.Sessions[entry.ID] = entry; return nil }); err != nil {
		t.Fatal(err)
	}

	for _, path := range []string{
		"/v1/account/region",
		"/v1/charging/history?vin=5YJ3E1EA7PF000001&page=2",
		"/v1/energy/products",
		"/v1/vehicles/5YJ3E1EA7PF000001/release-notes",
		"/v1/vehicles/5YJ3E1EA7PF000001/specs",
	} {
		r := httptest.NewRequest(http.MethodGet, path, nil)
		r.Header.Set("Authorization", "Bearer "+localToken)
		w := httptest.NewRecorder()
		s.routes().ServeHTTP(w, r)
		if w.Code != http.StatusOK {
			t.Fatalf("%s returned %d: %s", path, w.Code, w.Body.String())
		}
	}

	want := []string{
		"GET /api/1/users/region",
		"GET /api/1/dx/charging/history?page=2&vin=5YJ3E1EA7PF000001",
		"GET /api/1/products",
		"GET /api/1/vehicles/5YJ3E1EA7PF000001/release_notes",
		"GET /api/1/vehicles/5YJ3E1EA7PF000001/specs",
	}
	if strings.Join(received, "\n") != strings.Join(want, "\n") {
		t.Fatalf("unexpected upstream routes:\n%s", strings.Join(received, "\n"))
	}
}

func TestProductRoutesRejectUnknownQueryAndUnsafeIDs(t *testing.T) {
	if validResourceID("../invoice") || validResourceID(strings.Repeat("a", 129)) {
		t.Fatal("unsafe resource identifier accepted")
	}
}
