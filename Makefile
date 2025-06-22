# Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
# SPDX-License-Identifier: MIT

# Neovim executable to use to run our unit tests (which may be just the name of
# an executable in PATH or the absolute path of the executable on disk)
NVIM = nvim

.PHONY: all
all:
	@echo "This plugin is pure Lua. Nothing to build."
	@echo "Run \"$(MAKE) test\" to run the unit tests."

.PHONY: test
test:
	$(strip $(NVIM) \
		--headless \
		--noplugin \
		-u scripts/test-init.lua \
	)
