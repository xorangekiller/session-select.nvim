-- Copyright (c) 2026 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test wiping the current session's buffers before loading another session.
describe("clear_session", function()
    local Path = require("plenary.path")
    local stub = require("luassert.stub")
    local ss = require("session-select")

    local scratch_dir = Path:new(vim.uv.cwd(), ".scratch")
    local stubs = {}

    before_each(function()
        scratch_dir:mkdir({ exists_ok = true })
        ss.setup({ storage_path = ".scratch" })

        stubs = {
            confirm = stub.new(vim.fn, "confirm"),
        }
    end)

    after_each(function()
        vim.cmd("silent! %bwipeout!")

        if scratch_dir:exists() then
            scratch_dir:rm({ recursive = true })
        end

        for _, stubbed_func in pairs(stubs) do
            stubbed_func:revert()
        end
        stubs = {}
    end)

    it("wipe all buffers, windows and tabs when nothing is modified", function()
        local original = vim.api.nvim_get_current_buf()
        local buf2 = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(buf2)
        vim.cmd("tab split")
        local buf3 = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(buf3)

        assert.equal(3, #vim.api.nvim_list_bufs())
        assert.equal(2, #vim.api.nvim_list_tabpages())
        assert.equal(2, #vim.api.nvim_list_wins())

        assert.is_true(ss._clear_session())

        assert.stub(stubs.confirm).was_not.called()
        assert.is_false(vim.api.nvim_buf_is_valid(original))
        assert.is_false(vim.api.nvim_buf_is_valid(buf2))
        assert.equal(1, #vim.api.nvim_list_bufs())
        assert.equal(1, #vim.api.nvim_list_tabpages())
        assert.equal(1, #vim.api.nvim_list_wins())
    end)

    it("prompt before wiping modified buffers", function()
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })
        assert.is_true(vim.bo[buf].modified)

        stubs.confirm.returns(2)

        assert.is_true(ss._clear_session())

        assert.stub(stubs.confirm).was.called()
        assert.is_false(vim.api.nvim_buf_is_valid(buf))
    end)

    it("save modified buffers when requested", function()
        local test_file = Path:new(scratch_dir, "modified.txt")
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, test_file.filename)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "saved line" })
        assert.is_true(vim.bo[buf].modified)

        stubs.confirm.returns(1)

        assert.is_true(ss._clear_session())

        assert.stub(stubs.confirm).was.called()
        assert.is_false(vim.api.nvim_buf_is_valid(buf))
        assert.are.same({ "saved line" }, vim.fn.readfile(test_file.filename))
    end)

    it("leave modified buffers alone when canceled", function()
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })

        stubs.confirm.returns(3)

        assert.is_false(ss._clear_session())

        assert.stub(stubs.confirm).was.called()
        assert.is_true(vim.api.nvim_buf_is_valid(buf))
        assert.is_true(vim.bo[buf].modified)
    end)

    it("leave modified buffers alone when saving fails", function()
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })
        assert.is_true(vim.bo[buf].modified)

        stubs.confirm.returns(1)

        assert.is_false(ss._clear_session())

        assert.stub(stubs.confirm).was.called()
        assert.is_true(vim.api.nvim_buf_is_valid(buf))
        assert.is_true(vim.bo[buf].modified)
    end)
end)
