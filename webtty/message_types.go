package webtty

// Protocols defines the name of this protocol,
// which is supposed to be used to the subprotocol of Websockt streams.
var Protocols = []string{"webtty"}

const (
	// Unknown message type, maybe sent by a bug
	UnknownInput = '0'
	// User input typically from a keyboard
	Input = '1'
	// Ping to the server
	Ping = '2'
	// Notify that the browser size has been changed
	ResizeTerminal = '3'
	// Change encoding
	SetEncoding = '4'
)

const (
	// Unknown message type, maybe set by a bug
	UnknownOutput = '0'
	// Normal output to the terminal
	Output = '1'
	// Pong to the browser
	Pong = '2'
	// Set window title of the terminal
	SetWindowTitle = '3'
	// Set terminal preference
	SetPreferences = '4'
	// Make terminal to reconnect
	SetReconnect = '5'
	// Set the input buffer size
	SetBufferSize = '6'

	// Psmux layout update (JSON payload)
	PsmuxLayoutUpdate = '7'
	// Psmux pane-specific output
	PsmuxPaneOutput = '8'
	// Psmux session info
	PsmuxSessionInfo = 'A'
	// Psmux error
	PsmuxError = 'B'
)

// Psmux input message types (client -> server)
const (
	// Select a pane by ID
	PsmuxSelectPane = '5'
	// Select a window by ID
	PsmuxSelectWindow = '6'
	// Split current pane (payload: "h" or "v")
	PsmuxSplitPane = '7'
	// Close a pane by ID
	PsmuxClosePane = '8'
	// Create new window
	PsmuxNewWindow = 'D'
	// Switch session by name
	PsmuxSwitchSession = 'E'
)
