package webtty

import (
	"encoding/json"

	"github.com/pkg/errors"
	"webpsmux/pkg/psmux"
)

// PsmuxController interface for psmux operations
type PsmuxController interface {
	GetLayout() *psmux.Layout
	RefreshLayout() error
	SelectPane(paneID string) error
	SelectWindow(windowID string) error
	SwitchSession(sessionName string) error
	SplitPane(horizontal bool) error
	ClosePane(paneID string) error
	NewWindow() error
	Events() <-chan psmux.Event
}

// SetPsmuxController sets the psmux controller for the WebTTY instance
func (wt *WebTTY) SetPsmuxController(pc PsmuxController) {
	wt.psmuxCtrl = pc
}

// SendPsmuxLayout sends the current psmux layout to the client
func (wt *WebTTY) SendPsmuxLayout() error {
	if wt.psmuxCtrl == nil {
		return nil
	}

	layout := wt.psmuxCtrl.GetLayout()
	if layout == nil {
		return nil
	}

	data, err := json.Marshal(layout)
	if err != nil {
		return errors.Wrap(err, "failed to marshal psmux layout")
	}

	return wt.masterWrite(append([]byte{PsmuxLayoutUpdate}, data...))
}

// handlePsmuxMessage handles psmux-specific messages from the client
func (wt *WebTTY) handlePsmuxMessage(msgType byte, payload []byte) error {
	if wt.psmuxCtrl == nil {
		return nil // Silently ignore if no psmux controller
	}

	switch msgType {
	case PsmuxSelectPane:
		paneID := string(payload)
		if err := wt.psmuxCtrl.SelectPane(paneID); err != nil {
			return errors.Wrap(err, "failed to select pane")
		}
		return wt.SendPsmuxLayout()

	case PsmuxSelectWindow:
		windowID := string(payload)
		if err := wt.psmuxCtrl.SelectWindow(windowID); err != nil {
			return errors.Wrap(err, "failed to select window")
		}
		return wt.SendPsmuxLayout()

	case PsmuxSplitPane:
		horizontal := string(payload) == "h"
		if err := wt.psmuxCtrl.SplitPane(horizontal); err != nil {
			return errors.Wrap(err, "failed to split pane")
		}
		return wt.SendPsmuxLayout()

	case PsmuxClosePane:
		paneID := string(payload)
		if err := wt.psmuxCtrl.ClosePane(paneID); err != nil {
			return errors.Wrap(err, "failed to close pane")
		}
		return wt.SendPsmuxLayout()

	case PsmuxNewWindow:
		if err := wt.psmuxCtrl.NewWindow(); err != nil {
			return errors.Wrap(err, "failed to create new window")
		}
		return wt.SendPsmuxLayout()

	case PsmuxSwitchSession:
		sessionName := string(payload)
		if err := wt.psmuxCtrl.SwitchSession(sessionName); err != nil {
			return errors.Wrap(err, "failed to switch session")
		}
		return wt.SendPsmuxLayout()

	default:
		return errors.Errorf("unknown psmux message type: %c", msgType)
	}
}

// isPsmuxMessage returns true if the message type is a psmux-specific message
func isPsmuxMessage(msgType byte) bool {
	switch msgType {
	case PsmuxSelectPane, PsmuxSelectWindow, PsmuxSplitPane, PsmuxClosePane,
		PsmuxNewWindow, PsmuxSwitchSession:
		return true
	default:
		return false
	}
}
