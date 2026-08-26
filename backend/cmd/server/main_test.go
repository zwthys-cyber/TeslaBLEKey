package main

import (
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
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
	if !allowedCommands["door_lock"] || allowedCommands["erase_user_data"] {
		t.Fatal("unsafe command allowlist")
	}
	if validVehicleID("../etc/passwd") {
		t.Fatal("path traversal accepted")
	}
}
