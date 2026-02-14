package localcommand

import (
	"time"
)

type Option func(*LocalCommand)

func WithCloseTimeout(timeout time.Duration) Option {
	return func(lcmd *LocalCommand) {
		lcmd.closeTimeout = timeout
	}
}
