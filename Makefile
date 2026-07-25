SHELL := /bin/bash
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
SCRIPTS := rig

.PHONY: help check fmt install uninstall demo clean

help:
	@echo "make check      syntax + shellcheck + version agreement"
	@echo "make fmt        format with shfmt"
	@echo "make install    symlink rig into $(BINDIR)"
	@echo "make uninstall  remove the symlink"
	@echo "make demo       init + up + demo in a throwaway cell"
	@echo "make clean      remove the throwaway demo cell"

check:
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done
	@echo "syntax ok"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x $(SCRIPTS) && echo "shellcheck ok"; \
	else \
		echo "shellcheck not installed, skipped"; \
	fi
	@# rig is self-contained, so the version is inlined. Keep the VERSION
	@# file (release tooling reads it) from drifting away from the script.
	@a="$$(./rig version | awk '{print $$2}')"; b="$$(cat VERSION)"; \
	if [ "$$a" != "$$b" ]; then \
		echo "version mismatch: rig=$$a VERSION=$$b"; exit 1; \
	fi; \
	echo "version ok ($$a)"

fmt:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w -s $(SCRIPTS) && echo "formatted"; \
	else \
		echo "shfmt not installed, skipped"; \
	fi

install:
	@mkdir -p $(BINDIR)
	@ln -sf "$(CURDIR)/rig" "$(BINDIR)/rig"
	@echo "linked $(BINDIR)/rig -> $(CURDIR)/rig"

uninstall:
	@rm -f "$(BINDIR)/rig"
	@echo "removed $(BINDIR)/rig"

demo:
	./rig --cell make-demo init --force --workdir "$(CURDIR)"
	./rig --cell make-demo up
	./rig --cell make-demo demo

clean:
	-./rig --cell make-demo down
	rm -rf "$(HOME)/.local/share/rig/cells/make-demo"
