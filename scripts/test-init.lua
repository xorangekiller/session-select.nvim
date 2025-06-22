-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT
--
-- This is a minimal Neovim configuration used to bootstrap and run the
-- session-select.nvim unit tests instead of the user's configuration. It
-- provides a known-good, reproducible environment with plenary.nvim available
-- so that we can use its testing framework to run the unit tests.

-- The unit tests are written using plenary.nvim's testing framework. Plenary
-- isn't used by session-select.nvim itself. Just install it locally now so
-- that we can use it.
if not vim.env.PLENARY_PATH then
    local plenary_path = vim.fs.normalize(vim.uv.cwd() .. "/.deps/plenary.nvim")
    if not vim.uv.fs_stat(plenary_path) then
        if not vim.uv.fs_stat(".deps") then
            vim.fn.mkdir(".deps")
        end

        print("Cloning plenary.nvim...\n")
        vim.fn.system({
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/nvim-lua/plenary.nvim.git",
            plenary_path
        })
        if vim.v.shell_error ~= 0 then
            print("Failed to clone plenary.nvim\n")
            os.exit(1)
        end
    end
    vim.env.PLENARY_PATH = plenary_path
end

-- Now that plenary.nvim *should* be installed, ensure that it is in our
-- runtime path and import it so that we can use it to run the tests.
if vim.env.PLENARY_PATH then
    vim.opt.rtp:prepend(vim.env.PLENARY_PATH)
end
local test_harness = require("plenary.test_harness")

local test_directory = vim.fs.normalize(vim.uv.cwd() .. "/tests")
print("Running the unit tests in " .. test_directory .. "\n")
test_harness.test_directory(test_directory, {
    -- Run our unit tests sequentially rather than in parallel because they
    -- operate on session files in the same directory. A user would never run
    -- commands in this plugin in parallel anyway.
    sequential = true,
    -- Run all of the unit tests, even if one of them failed. This is helpful
    -- for telling just how much is broken if anything is broken.
    keep_going = true,
})

-- test_harness.test_directory() should never return. It will either print its
-- status and exit with an error code if one or more of the unit tests failed,
-- or it will print a summary of the tests that were run and exit with 0 if all
-- of the unit tests succeeded. If you ever see this message, something didn't
-- work as expected.
print("Error: Test runner returned unexpectedly.\n")
os.exit(1)
