package psmux

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

var (
	sessionRegex = regexp.MustCompile(`^(\S+): (\d+) windows \(created [^)]+\) \[(\d+)x(\d+)\](?: \(attached\))?$`)
	windowRegex  = regexp.MustCompile(`^(\d+): (\S+?)(\*)? \((\d+) panes?\) \[(\d+)x(\d+)\]$`)
	paneRegex    = regexp.MustCompile(`^(%\d+): \[(\d+)x(\d+)\]`)
)

func ParseSessions(output string) ([]Session, error) {
	var sessions []Session
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		matches := sessionRegex.FindStringSubmatch(line)
		if matches == nil {
			return nil, fmt.Errorf("failed to parse session line: %s", line)
		}
		winCount, _ := strconv.Atoi(matches[2])
		attached := strings.Contains(line, "(attached)")
		sessions = append(sessions, Session{
			ID:       matches[1],
			Name:     matches[1],
			Windows:  winCount,
			Attached: attached,
		})
	}
	return sessions, nil
}

func ParseWindows(output string) ([]Window, error) {
	var windows []Window
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		matches := windowRegex.FindStringSubmatch(line)
		if matches == nil {
			return nil, fmt.Errorf("failed to parse window line: %s", line)
		}
		idx, _ := strconv.Atoi(matches[1])
		active := matches[3] == "*"
		name := matches[2]
		windows = append(windows, Window{
			ID:     fmt.Sprintf("@%d", idx),
			Name:   name,
			Index:  idx,
			Active: active,
		})
	}
	return windows, nil
}

func ParsePanes(output string) ([]Pane, error) {
	var panes []Pane
	for i, line := range strings.Split(strings.TrimSpace(output), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		matches := paneRegex.FindStringSubmatch(line)
		if matches == nil {
			return nil, fmt.Errorf("failed to parse pane line: %s", line)
		}
		width, _ := strconv.Atoi(matches[2])
		height, _ := strconv.Atoi(matches[3])
		panes = append(panes, Pane{
			ID:     matches[1],
			Index:  i,
			Active: i == 0,
			Width:  width,
			Height: height,
		})
	}
	return panes, nil
}
