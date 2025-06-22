-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test the compatibility layer for vim.fs.joinpath().
describe("joinpath_compat", function()
    local ss = require("session-select")

    -- The compatibility layer is disabled by default on Neovim 0.10.0 and
    -- later because it isn't needed. In that case, some of these tests have no
    -- meaning. Only run them on sufficiently new versions of Neovim.
    if vim.fn.has("nvim-0.10.0") == 1 then
        it("joinpath compat is not needed by default", function()
            ss.setup({})
            assert.is_false(ss.options.debug.joinpath_compat)
            assert.is_false(ss._need_joinpath_compat())
        end)

        it("joinpath compat will always be used if requested", function()
            ss.setup({ debug = { joinpath_compat = true } })
            assert.is_true(ss.options.debug.joinpath_compat)
            assert.is_true(ss._need_joinpath_compat())
        end)

        it("all debug options explicitly disabled", function()
            ss.setup({ debug = {} })
            assert.is_false(ss.options.debug.joinpath_compat)
            assert.is_false(ss._need_joinpath_compat())
        end)

        it("joinpath no compat with single path", function()
            ss.setup({})
            assert.is_false(ss.options.debug.joinpath_compat)
            assert.equal("/tmp/sessions", ss._joinpath("/tmp/sessions"))
        end)

        it("joinpath no compat with multiple parts", function()
            ss.setup({})
            assert.is_false(ss.options.debug.joinpath_compat)
            assert.equal(
                "/tmp/sessions/test.sess",
                ss._joinpath("/tmp/sessions", "test.sess")
            )
        end)

        it("joinpath no compat with empty path", function()
            ss.setup({})
            assert.is_false(ss.options.debug.joinpath_compat)
            assert.equal("", ss._joinpath(""))
        end)
    end

    it("joinpath compat with single path", function()
        ss.setup({ debug = { joinpath_compat = true } })
        assert.is_true(ss.options.debug.joinpath_compat)
        assert.is_true(ss._need_joinpath_compat())
        assert.equal("/tmp/sessions", ss._joinpath("/tmp/sessions"))
    end)

    it("joinpath compat with multiple parts", function()
        ss.setup({ debug = { joinpath_compat = true } })
        assert.is_true(ss.options.debug.joinpath_compat)
        assert.is_true(ss._need_joinpath_compat())
        assert.equal(
            "/tmp/sessions/test.sess",
            ss._joinpath("/tmp/sessions", "test.sess")
        )
    end)

    it("joinpath compat with empty path", function()
        ss.setup({ debug = { joinpath_compat = true } })
        assert.is_true(ss.options.debug.joinpath_compat)
        assert.is_true(ss._need_joinpath_compat())
        assert.equal("", ss._joinpath(""))
    end)

    it("joinpath compat with no path", function()
        ss.setup({ debug = { joinpath_compat = true } })
        assert.is_true(ss.options.debug.joinpath_compat)
        assert.is_true(ss._need_joinpath_compat())
        assert.equal("", ss._joinpath())
    end)
end)
