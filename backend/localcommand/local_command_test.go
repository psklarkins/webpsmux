package localcommand

import (
	"reflect"
	"testing"
	"time"
)

func TestNewFactory(t *testing.T) {
	factory, err := NewFactory("cmd.exe", []string{}, &Options{CloseSignal: 0, CloseTimeout: 321})
	if err != nil {
		t.Errorf("NewFactory() returned error")
		return
	}
	if factory.command != "cmd.exe" {
		t.Errorf("factory.command = %v, expected %v", factory.command, "cmd.exe")
	}
	if !reflect.DeepEqual(factory.argv, []string{}) {
		t.Errorf("factory.argv = %v, expected %v", factory.argv, []string{})
	}
	if !reflect.DeepEqual(factory.options, &Options{CloseSignal: 0, CloseTimeout: 321}) {
		t.Errorf("factory.options = %v, expected %v", factory.options, &Options{CloseSignal: 0, CloseTimeout: 321})
	}

	slave, err := factory.New(nil, nil)
	if err != nil {
		t.Errorf("factory.New() returned error: %v", err)
		return
	}
	lcmd := slave.(*LocalCommand)
	if lcmd.closeTimeout != time.Second*321 {
		t.Errorf("lcmd.closeTimeout = %v, expected %v", lcmd.closeTimeout, time.Second*321)
	}
	_ = slave.Close()
}
