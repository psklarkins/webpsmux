package localcommand

import (
	"context"
	"os"
	"strings"
	"time"

	"github.com/UserExistsError/conpty"
	"github.com/pkg/errors"
)

const (
	DefaultCloseTimeout = 10 * time.Second
)

type LocalCommand struct {
	command string
	argv    []string

	closeTimeout time.Duration

	cpty      *conpty.ConPty
	ptyClosed chan struct{}
}

func New(command string, argv []string, headers map[string][]string, options ...Option) (*LocalCommand, error) {
	cmdLine := command
	if len(argv) > 0 {
		cmdLine = command + " " + strings.Join(argv, " ")
	}

	env := append(os.Environ(), "TERM=xterm-256color")
	for key, values := range headers {
		h := "HTTP_" + strings.Replace(strings.ToUpper(key), "-", "_", -1) + "=" + strings.Join(values, ",")
		env = append(env, h)
	}

	cpty, err := conpty.Start(cmdLine, conpty.ConPtyDimensions(80, 24), conpty.ConPtyEnv(env))
	if err != nil {
		return nil, errors.Wrapf(err, "failed to start command `%s`", command)
	}
	ptyClosed := make(chan struct{})

	lcmd := &LocalCommand{
		command: command,
		argv:    argv,

		closeTimeout: DefaultCloseTimeout,

		cpty:      cpty,
		ptyClosed: ptyClosed,
	}

	for _, option := range options {
		option(lcmd)
	}

	go func() {
		defer func() {
			lcmd.cpty.Close()
			close(lcmd.ptyClosed)
		}()

		_, _ = lcmd.cpty.Wait(context.Background())
	}()

	return lcmd, nil
}

func (lcmd *LocalCommand) Read(p []byte) (n int, err error) {
	return lcmd.cpty.Read(p)
}

func (lcmd *LocalCommand) Write(p []byte) (n int, err error) {
	return lcmd.cpty.Write(p)
}

func (lcmd *LocalCommand) Close() error {
	lcmd.cpty.Close()
	for {
		select {
		case <-lcmd.ptyClosed:
			return nil
		case <-lcmd.closeTimeoutC():
			return nil
		}
	}
}

func (lcmd *LocalCommand) WindowTitleVariables() map[string]interface{} {
	return map[string]interface{}{
		"command": lcmd.command,
		"argv":    lcmd.argv,
		"pid":     lcmd.cpty.Pid(),
	}
}

func (lcmd *LocalCommand) ResizeTerminal(width int, height int) error {
	return lcmd.cpty.Resize(width, height)
}

func (lcmd *LocalCommand) closeTimeoutC() <-chan time.Time {
	if lcmd.closeTimeout >= 0 {
		return time.After(lcmd.closeTimeout)
	}

	return make(chan time.Time)
}
