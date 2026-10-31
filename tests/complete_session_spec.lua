-- Copyright (c) 2026 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test tab completion for the session commands.
describe("complete_session", function()
    local Path = require("plenary.path")
    local ss = require("session-select")

    local scratch_dir = Path:new(vim.uv.cwd(), ".scratch")
    local missing_dir = Path:new(vim.uv.cwd(), ".scratch_missing")
    local alpha_sess = Path:new(scratch_dir, "alpha.sess")
    local beta_sess = Path:new(scratch_dir, "beta.sess")

    local original_wildignorecase

    -- Ensure that we start each test in a known state with a few saved
    -- sessions that may be completed.
    before_each(function()
        scratch_dir:mkdir({ exists_ok = true })
        alpha_sess:write("", "w")
        beta_sess:write("", "w")
        Path:new(scratch_dir, "subdir"):mkdir({ exists_ok = true })
        Path:new(scratch_dir, "alpha.sess.tmpfiltered"):write("", "w")

        ss.setup({ storage_path = ".scratch" })

        original_wildignorecase = vim.o.wildignorecase
    end)

    -- Reset to a known good state after each test case.
    after_each(function()
        vim.o.wildignorecase = original_wildignorecase

        if scratch_dir:exists() then
            scratch_dir:rm({ recursive = true })
        end
        if missing_dir:exists() then
            missing_dir:rm({ recursive = true })
        end
    end)

    it("complete all sessions with an empty prefix", function()
        assert.are.same({ "alpha.sess", "beta.sess" }, ss._complete_session(""))
    end)

    it("complete only sessions matching the prefix", function()
        assert.are.same({ "alpha.sess" }, ss._complete_session("a"))
        assert.are.same({ "alpha.sess" }, ss._complete_session("alpha"))
    end)

    it("complete nothing when no session matches the prefix", function()
        assert.are.same({}, ss._complete_session("missing"))
    end)

    it("complete nothing when the storage directory does not exist", function()
        ss.setup({ storage_path = ".scratch_missing" })

        assert.are.same({}, ss._complete_session(""))
    end)

    it("ignore case when wildignorecase is enabled", function()
        vim.o.wildignorecase = true

        assert.are.same({ "alpha.sess" }, ss._complete_session("A"))
    end)

    it("wire completion into all three commands", function()
        assert.are.same(
            { "alpha.sess" },
            vim.fn.getcompletion("LoadSession al", "cmdline")
        )
        assert.are.same(
            { "beta.sess" },
            vim.fn.getcompletion("LoadSession! b", "cmdline")
        )
        assert.are.same(
            { "alpha.sess" },
            vim.fn.getcompletion("DeleteSession al", "cmdline")
        )
        assert.are.same(
            { "alpha.sess" },
            vim.fn.getcompletion("SaveSession al", "cmdline")
        )
    end)
end)
