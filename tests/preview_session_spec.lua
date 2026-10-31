-- Copyright (c) 2026 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test the session file preview used by the load and delete pickers.
describe("preview_session", function()
    local Path = require("plenary.path")
    local ss = require("session-select")

    local scratch_dir = Path:new(vim.uv.cwd(), ".scratch")
    local test_sess = Path:new(scratch_dir, "preview.sess")
    local empty_sess = Path:new(scratch_dir, "empty.sess")
    local outside_sess = Path:new(vim.uv.cwd(), "preview-outside.sess")

    local buffers = {}

    local function preview(name)
        local result = ss._preview_session(name)
        table.insert(buffers, result.buf)
        return result
    end

    local function lines(buf)
        return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    end

    before_each(function()
        scratch_dir:mkdir({ exists_ok = true })
        test_sess:write("set test = 1\nlet other = 2\n", "w")
        empty_sess:write("", "w")
        outside_sess:write("outside\n", "w")

        ss.setup({ storage_path = ".scratch" })
        buffers = {}
    end)

    after_each(function()
        for _, buf in ipairs(buffers) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        buffers = {}

        if scratch_dir:exists() then
            scratch_dir:rm({ recursive = true })
        end
        if outside_sess:exists() then
            outside_sess:rm()
        end
    end)

    it("return the raw contents of the session file", function()
        local result = preview("preview.sess")

        assert.same({ "set test = 1", "let other = 2" }, lines(result.buf))
    end)

    it("return an empty buffer for an empty session file", function()
        local result = preview("empty.sess")

        assert.same({ "" }, lines(result.buf))
    end)

    it("report an error for a missing session file", function()
        local result = preview("missing.sess")

        local preview_lines = lines(result.buf)
        assert.equal(1, #preview_lines)
        assert.truthy(preview_lines[1]:find("unable to read session", 1, true))
        assert.truthy(preview_lines[1]:find("missing.sess", 1, true))
    end)

    it("configure the preview buffer", function()
        local result = preview("preview.sess")

        assert.equal("vim", vim.bo[result.buf].filetype)
        assert.equal("wipe", vim.bo[result.buf].bufhidden)
        assert.is_false(vim.bo[result.buf].modifiable)
    end)

    it("reuse the preview buffer for subsequent previews", function()
        local first = preview("preview.sess")
        local second = preview("empty.sess")

        assert.equal(first.buf, second.buf)
        assert.same({ "" }, lines(second.buf))
    end)

    it("do not read files outside the session directory", function()
        scratch_dir:joinpath("preview-outside.sess"):write("inside\n", "w")

        local result = preview("../preview-outside.sess")

        assert.same({ "inside" }, lines(result.buf))
    end)
end)
