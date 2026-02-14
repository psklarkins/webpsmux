package psmux

import (
	"testing"
)

func TestParseSessions_Single(t *testing.T) {
	output := `default: 1 windows (created Sat Feb 14 11:06:12 2026) [140x20] (attached)`
	sessions, err := ParseSessions(output)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(sessions) != 1 {
		t.Fatalf("expected 1 session, got %d", len(sessions))
	}
	s := sessions[0]
	if s.Name != "default" {
		t.Errorf("expected name 'default', got %q", s.Name)
	}
	if s.Windows != 1 {
		t.Errorf("expected 1 window, got %d", s.Windows)
	}
	if !s.Attached {
		t.Error("expected attached=true")
	}
}

func TestParseSessions_Multiple(t *testing.T) {
	output := `default: 2 windows (created Sat Feb 14 11:06:12 2026) [140x20] (attached)
build: 1 windows (created Sat Feb 14 12:00:00 2026) [120x30]`
	sessions, err := ParseSessions(output)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(sessions) != 2 {
		t.Fatalf("expected 2 sessions, got %d", len(sessions))
	}
	if sessions[0].Name != "default" {
		t.Errorf("expected first session 'default', got %q", sessions[0].Name)
	}
	if sessions[1].Attached {
		t.Error("expected second session not attached")
	}
}

func TestParseWindows_Single(t *testing.T) {
	output := `0: pwsh* (2 panes) [140x20]`
	windows, err := ParseWindows(output)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(windows) != 1 {
		t.Fatalf("expected 1 window, got %d", len(windows))
	}
	w := windows[0]
	if w.Name != "pwsh" {
		t.Errorf("expected name 'pwsh', got %q", w.Name)
	}
	if w.Index != 0 {
		t.Errorf("expected index 0, got %d", w.Index)
	}
	if !w.Active {
		t.Error("expected active=true")
	}
	if w.ID != "@0" {
		t.Errorf("expected ID '@0', got %q", w.ID)
	}
}

func TestParseWindows_Multiple(t *testing.T) {
	output := `0: pwsh* (1 panes) [140x20]
1: vim (2 panes) [140x20]
2: logs (1 panes) [140x20]`
	windows, err := ParseWindows(output)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(windows) != 3 {
		t.Fatalf("expected 3 windows, got %d", len(windows))
	}
	if !windows[0].Active {
		t.Error("expected first window active")
	}
	if windows[1].Active {
		t.Error("expected second window not active")
	}
	if windows[1].Name != "vim" {
		t.Errorf("expected name 'vim', got %q", windows[1].Name)
	}
}

func TestParsePanes_Single(t *testing.T) {
	output := `%2: [140x19] mouse=None/Default alt=false`
	panes, err := ParsePanes(output)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(panes) != 1 {
		t.Fatalf("expected 1 pane, got %d", len(panes))
	}
	p := panes[0]
	if p.ID != "%2" {
		t.Errorf("expected ID '%%2', got %q", p.ID)
	}
	if p.Width != 140 {
		t.Errorf("expected width 140, got %d", p.Width)
	}
	if p.Height != 19 {
		t.Errorf("expected height 19, got %d", p.Height)
	}
	if !p.Active {
		t.Error("expected first pane active")
	}
}

func TestParsePanes_Multiple(t *testing.T) {
	output := `%2: [70x19] mouse=None/Default alt=false
%3: [69x19] mouse=None/Default alt=false`
	panes, err := ParsePanes(output)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(panes) != 2 {
		t.Fatalf("expected 2 panes, got %d", len(panes))
	}
	if panes[0].ID != "%2" {
		t.Errorf("expected first pane ID '%%2', got %q", panes[0].ID)
	}
	if panes[1].ID != "%3" {
		t.Errorf("expected second pane ID '%%3', got %q", panes[1].ID)
	}
	if !panes[0].Active {
		t.Error("expected first pane active")
	}
	if panes[1].Active {
		t.Error("expected second pane not active")
	}
	if panes[0].Width != 70 {
		t.Errorf("expected width 70, got %d", panes[0].Width)
	}
}

func TestParseSessions_InvalidLine(t *testing.T) {
	output := `not a valid line`
	_, err := ParseSessions(output)
	if err == nil {
		t.Error("expected error for invalid input")
	}
}

func TestParseWindows_InvalidLine(t *testing.T) {
	output := `garbage data`
	_, err := ParseWindows(output)
	if err == nil {
		t.Error("expected error for invalid input")
	}
}

func TestParsePanes_InvalidLine(t *testing.T) {
	output := `not a pane`
	_, err := ParsePanes(output)
	if err == nil {
		t.Error("expected error for invalid input")
	}
}
