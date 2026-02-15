package server

import (
	"net/http/httptest"
	"testing"
)

func TestExtractClientIP(t *testing.T) {
	tests := []struct {
		name       string
		remoteAddr string
		xff        string
		xri        string
		expected   string
	}{
		{name: "remote ipv4", remoteAddr: "10.0.0.1:1234", expected: "10.0.0.1"},
		{name: "remote ipv6", remoteAddr: "[2001:db8::1]:1234", expected: "2001:db8::1"},
		{name: "xff takes priority", remoteAddr: "10.0.0.1:1234", xff: "192.168.1.2, 10.0.0.1", expected: "192.168.1.2"},
		{name: "xff with port", remoteAddr: "10.0.0.1:1234", xff: "[2001:db8::2]:4567", expected: "2001:db8::2"},
		{name: "x-real-ip fallback", remoteAddr: "10.0.0.1:1234", xri: "172.16.1.3", expected: "172.16.1.3"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "http://example.com", nil)
			r.RemoteAddr = tc.remoteAddr
			if tc.xff != "" {
				r.Header.Set("X-Forwarded-For", tc.xff)
			}
			if tc.xri != "" {
				r.Header.Set("X-Real-IP", tc.xri)
			}

			if got := extractClientIP(r); got != tc.expected {
				t.Fatalf("expected %q, got %q", tc.expected, got)
			}
		})
	}
}
