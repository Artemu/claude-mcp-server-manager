# MCP Manager — build automation
# Run `make` or `make help` to see available targets.

APP_NAME := MCP Manager
APP_BUNDLE := build/$(APP_NAME).app

.DEFAULT_GOAL := help
.PHONY: help build release icon app run clean check

help: ## Show this help
	@echo "MCP Manager — make targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build a debug binary (fast)
	swift build

release: ## Build an optimized release binary
	swift build -c release

icon: ## Regenerate Resources/AppIcon.icns from make-icon.swift
	./make-icon.sh

app: ## Build the distributable "MCP Manager.app" bundle
	./build-app.sh

run: app ## Build and launch the app
	open "$(APP_BUNDLE)"

check: ## Compile in release mode to catch errors (used by CI)
	swift build -c release

clean: ## Remove all build artifacts
	swift package clean
	rm -rf .build build
