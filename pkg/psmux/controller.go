package psmux

import (
	"fmt"
	"os/exec"
	"strings"
	"sync"
)

type Controller struct {
	sessionName string
	layoutCache *Layout
	layoutMu    sync.RWMutex
	eventChan   chan Event
	closeChan   chan struct{}
}

func NewController(sessionName string) (*Controller, error) {
	c := &Controller{
		sessionName: sessionName,
		eventChan:   make(chan Event, 100),
		closeChan:   make(chan struct{}),
	}
	return c, nil
}

func (c *Controller) Start() error {
	cmd := exec.Command("psmux", "has-session", "-t", c.sessionName)
	if err := cmd.Run(); err != nil {
		createCmd := exec.Command("psmux", "new-session", "-d", "-s", c.sessionName)
		if createErr := createCmd.Run(); createErr != nil {
			return fmt.Errorf("failed to create psmux session %s: %w", c.sessionName, createErr)
		}
	}

	if err := c.RefreshLayout(); err != nil {
		return fmt.Errorf("failed to get initial layout: %w", err)
	}

	return nil
}

func (c *Controller) Stop() error {
	close(c.closeChan)
	return nil
}

func (c *Controller) Events() <-chan Event {
	return c.eventChan
}

func (c *Controller) GetLayout() *Layout {
	c.layoutMu.RLock()
	defer c.layoutMu.RUnlock()
	return c.layoutCache
}

func (c *Controller) RefreshLayout() error {
	sessionsOut, err := c.runPsmux("ls")
	if err != nil {
		return fmt.Errorf("failed to list sessions: %w", err)
	}

	sessions, err := ParseSessions(sessionsOut)
	if err != nil {
		return fmt.Errorf("failed to parse sessions: %w", err)
	}

	layout := &Layout{
		SessionName: c.sessionName,
	}

	for i := range sessions {
		sessions[i].Active = sessions[i].Name == c.sessionName
		if sessions[i].Active {
			layout.SessionID = sessions[i].ID
		}
	}
	layout.Sessions = sessions

	windowsOut, err := c.runPsmux("list-windows", "-t", c.sessionName)
	if err != nil {
		return fmt.Errorf("failed to list windows: %w", err)
	}

	windows, err := ParseWindows(windowsOut)
	if err != nil {
		return fmt.Errorf("failed to parse windows: %w", err)
	}

	for i := range windows {
		win := &windows[i]
		if win.Active {
			layout.ActiveWinID = win.ID
		}

		target := fmt.Sprintf("%s:%d", c.sessionName, win.Index)
		panesOut, err := c.runPsmux("list-panes", "-t", target)
		if err != nil {
			continue
		}

		panes, err := ParsePanes(panesOut)
		if err != nil {
			continue
		}

		if win.Active && len(panes) > 0 {
			layout.ActivePaneID = panes[0].ID
		}

		win.Panes = panes
	}

	layout.Windows = windows

	c.layoutMu.Lock()
	c.layoutCache = layout
	c.layoutMu.Unlock()

	return nil
}

func (c *Controller) SelectPane(paneID string) error {
	_, err := c.runPsmux("select-pane", "-t", paneID)
	if err != nil {
		return err
	}
	c.RefreshLayout()
	return nil
}

func (c *Controller) SelectWindow(windowID string) error {
	_, err := c.runPsmux("select-window", "-t", windowID)
	if err != nil {
		return err
	}
	c.RefreshLayout()
	return nil
}

func (c *Controller) SwitchSession(sessionName string) error {
	_, err := c.runPsmux("switch-client", "-t", sessionName)
	if err != nil {
		return err
	}
	c.sessionName = sessionName
	c.RefreshLayout()
	return nil
}

func (c *Controller) SplitPane(horizontal bool) error {
	flag := "-v"
	if horizontal {
		flag = "-h"
	}
	_, err := c.runPsmux("split-window", "-t", c.sessionName, flag)
	if err != nil {
		return err
	}
	c.RefreshLayout()
	return nil
}

func (c *Controller) ClosePane(paneID string) error {
	_, err := c.runPsmux("kill-pane", "-t", paneID)
	if err != nil {
		return err
	}
	c.RefreshLayout()
	return nil
}

func (c *Controller) NewWindow() error {
	_, err := c.runPsmux("new-window", "-t", c.sessionName)
	if err != nil {
		return err
	}
	c.RefreshLayout()
	return nil
}

func (c *Controller) runPsmux(args ...string) (string, error) {
	cmd := exec.Command("psmux", args...)
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("psmux command failed (%s): %w", strings.Join(args, " "), err)
	}
	return string(output), nil
}
