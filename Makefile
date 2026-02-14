# WebPsmux Makefile
# Builds Windows binary for psmux web terminal

VERSION ?= $(shell git describe --tags 2>/dev/null || echo "dev")
GIT_COMMIT = $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME = $(shell date -u '+%Y-%m-%d_%H:%M:%S')
BUILD_OPTIONS = -ldflags "-s -w -X main.Version=$(VERSION) -X main.GitCommit=$(GIT_COMMIT)"

OUTPUT_DIR = ./builds
BINARY_NAME = webpsmux

export CGO_ENABLED=0

.PHONY: all build clean test install help

# Default target
all: build

# Sync resources to bindata (for embedding)
sync-assets:
	@cp resources/index.html bindata/static/index.html
	@cp -r resources/js/* bindata/static/js/

# Build for Windows
build: sync-assets
	@echo "Building $(BINARY_NAME) $(VERSION)..."
	GOOS=windows GOARCH=amd64 go build $(BUILD_OPTIONS) -o $(BINARY_NAME).exe .
	@echo "Done: ./$(BINARY_NAME).exe"

# Install to GOPATH/bin
install:
	go install $(BUILD_OPTIONS) .

# Run tests
test:
	go test ./...
	go vet ./...

# Clean build artifacts
clean:
	rm -rf $(BINARY_NAME).exe $(OUTPUT_DIR)

# Copy assets to bindata (for development)
assets:
	cp resources/index.html bindata/static/index.html
	cp resources/js/webtmux.js bindata/static/js/
	cp resources/js/components/*.js bindata/static/js/components/

# Development build with assets
dev: assets build

help:
	@echo "WebPsmux Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make              Build for Windows"
	@echo "  make build        Build for Windows"
	@echo "  make install      Install to GOPATH/bin"
	@echo "  make test         Run tests"
	@echo "  make clean        Remove build artifacts"
	@echo "  make assets       Copy assets to bindata"
	@echo "  make dev          Build with fresh assets"
	@echo "  make help         Show this help"
