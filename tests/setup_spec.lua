-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test the setup function to ensure that options are preserved as expected.
describe("setup_options", function()
    local ss = require("session-select")

    it("setup with empty table (all defaults)", function()
        ss.setup({})
        assert.truthy(ss.options.storage_path)
        assert.is_true(ss.options.register_commands)
        assert.is_false(ss.options.filter.nomap)
        assert.is_false(ss.options.debug.joinpath_compat)
    end)

    it("setup with nil options (all defaults)", function()
        ss.setup()
        assert.truthy(ss.options.storage_path)
        assert.is_true(ss.options.register_commands)
        assert.is_false(ss.options.filter.nomap)
        assert.is_false(ss.options.debug.joinpath_compat)
    end)

    it("setup with overridden storage path", function()
        ss.setup({ storage_path = "/tmp/nvim/sessions" })
        assert.equal("/tmp/nvim/sessions", ss.options.storage_path)
        assert.is_true(ss.options.register_commands)
        assert.is_false(ss.options.filter.nomap)
        assert.is_false(ss.options.debug.joinpath_compat)
    end)

    it("setup with relative storage path", function()
        local abs_sessions_path = vim.fs.normalize(
            vim.uv.cwd() .. "/.scratch/sessions"
        )
        assert.truthy(abs_sessions_path)
        assert.falsy(vim.uv.fs_stat(abs_sessions_path))

        ss.setup({ storage_path = ".scratch/sessions" })

        assert.equal(abs_sessions_path, ss.options.storage_path)
    end)

    it("setup with no filter options", function()
        ss.setup({ filter = {} })
        assert.truthy(ss.options.storage_path)
        assert.is_true(ss.options.register_commands)
        assert.is_false(ss.options.filter.nomap)
        assert.is_false(ss.options.debug.joinpath_compat)
    end)

    it("setup with overridden filter options", function()
        ss.setup({ filter = { nomap = true } })
        assert.truthy(ss.options.storage_path)
        assert.is_true(ss.options.register_commands)
        assert.is_true(ss.options.filter.nomap)
        assert.is_false(ss.options.debug.joinpath_compat)
    end)

    it("setup with no debug options", function()
        ss.setup({ debug = {} })
        assert.truthy(ss.options.storage_path)
        assert.is_true(ss.options.register_commands)
        assert.is_false(ss.options.filter.nomap)
        assert.is_false(ss.options.debug.joinpath_compat)
    end)

    it("setup with overridden debug options", function()
        ss.setup({ debug = { joinpath_compat = true } })
        assert.truthy(ss.options.storage_path)
        assert.is_true(ss.options.register_commands)
        assert.is_false(ss.options.filter.nomap)
        assert.is_true(ss.options.debug.joinpath_compat)
    end)
end)
