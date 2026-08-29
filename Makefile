# Makefile for ngx-cert-manager

.PHONY: help lint test deb install uninstall clean

SHELL := /usr/bin/env bash
PREFIX ?= /usr/local

help:
	@echo "ngx-cert-manager Development & Packaging Makefile"
	@echo "=================================================="
	@echo "make lint        - Run syntax checks (shellcheck / bash -n)"
	@echo "make test        - Run all test suites in tests/"
	@echo "make deb         - Build Debian/Ubuntu .deb package for APT distribution"
	@echo "make install     - Install to system (PREFIX=$(PREFIX))"
	@echo "make uninstall   - Remove from system (PREFIX=$(PREFIX))"
	@echo "make clean       - Clean temporary test artifacts and builds"

lint:
	@echo "[*] Checking bash syntax on all shell scripts and entrypoints..."
	@for file in ngx-cert-manager main.sh install.sh config.env lib/*.sh scripts/*.sh tests/*.sh examples/*.sh; do \
		if [ -f "$$file" ]; then \
			bash -n "$$file" || exit 1; \
			echo "  ✓ Syntax OK: $$file"; \
		fi \
	done
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "[*] Running shellcheck analysis..."; \
		shellcheck -x ngx-cert-manager lib/*.sh || true; \
	else \
		echo "[!] shellcheck not found, bash -n syntax checks passed."; \
	fi

test:
	@echo "[*] Running test suites..."
	@bash tests/run_all.sh

deb:
	@echo "[*] Building Debian package..."
	@bash scripts/build_deb.sh

install:
	@echo "[*] Installing ngx-cert-manager to $(PREFIX)..."
	@PREFIX=$(PREFIX) ./install.sh install

uninstall:
	@echo "[*] Uninstalling ngx-cert-manager from $(PREFIX)..."
	@PREFIX=$(PREFIX) ./install.sh uninstall

clean:
	@echo "[*] Cleaning up temporary files and dist/..."
	@rm -rf tests/tmp tests/fixtures/tmp *.tmp .backup/ dist/
