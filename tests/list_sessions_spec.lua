-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test listing sessions that have previously been saved.
describe("list_sessions", function()
    local Path = require("plenary.path")
    local ss = require("session-select")

    local scratch_dir = Path:new(vim.uv.cwd(), ".scratch")
    local test_sess = Path:new(scratch_dir, "test.sess")
    local test_filtered = Path:new(test_sess.filename .. ".tmpfiltered")
    local empty_sess = Path:new(scratch_dir, "empty.sess")

    -- Create the sessions to list (and subdirectories and other files not to)
    -- before each test.
    before_each(function()
        scratch_dir:mkdir({ exists_ok = true })
        test_sess:write("", "w")
        test_filtered:write("", "w")
        empty_sess:write("", "w")

        ss.setup({ storage_path = ".scratch" })
    end)

    -- Remove the session directory to reset to our initial state.
    after_each(function()
        if scratch_dir:exists() then
            scratch_dir:rm({ recursive = true })
        end
    end)

    it("list the session file names in the sessions directory", function()
        ss._list_sessions()

        assert.are.same({ "empty.sess", "test.sess" }, ss._list_sessions())
        assert.truthy(test_sess:exists())
        assert.falsy(test_filtered:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("list the sessions after a session has been added", function()
        ss._list_sessions()

        assert.are.same({ "empty.sess", "test.sess" }, ss._list_sessions())
        assert.truthy(test_sess:exists())
        assert.falsy(test_filtered:exists())
        assert.truthy(empty_sess:exists())

        Path:new(scratch_dir, "new.sess"):write("", "w")

        ss._list_sessions()

        assert.are.same(
            { "empty.sess", "new.sess", "test.sess" },
            ss._list_sessions()
        )
    end)

    it("list the sessions after a session has been deleted", function()
        ss._list_sessions()

        assert.are.same({ "empty.sess", "test.sess" }, ss._list_sessions())
        assert.truthy(test_sess:exists())
        assert.falsy(test_filtered:exists())
        assert.truthy(empty_sess:exists())

        test_sess:rm()

        ss._list_sessions()

        assert.are.same({ "empty.sess" }, ss._list_sessions())
        assert.falsy(test_sess:exists())
        assert.falsy(test_filtered:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("ignore anything that is not a file (including subdirectories)", function()
        local subdir_1 = Path:new(scratch_dir, "subdir_1")
        local subdir_2 = Path:new(scratch_dir, "subdir_2")

        subdir_1:mkdir({ exists_ok = true })
        subdir_2:mkdir({ exists_ok = true })

        Path:new(subdir_1, "file_1.sess"):write("", "w")
        Path:new(subdir_2, "file_2.sess"):write("", "w")

        ss._list_sessions()

        assert.are.same({ "empty.sess", "test.sess" }, ss._list_sessions())
        assert.truthy(test_sess:exists())
        assert.falsy(test_filtered:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("do not return any sessions if the sessions directory does not exist", function()
        scratch_dir:rm({ recursive = true })

        ss._list_sessions()

        assert.are.same({}, ss._list_sessions())
    end)

    it("do not return any sessions if the sessions directory is empty", function()
        test_sess:rm()
        test_filtered:rm()
        empty_sess:rm()

        ss._list_sessions()

        assert.are.same({}, ss._list_sessions())
        assert.falsy(test_sess:exists())
        assert.falsy(test_filtered:exists())
        assert.falsy(empty_sess:exists())
    end)

    it("delete any remaining temporary filter files", function()
        assert.truthy(test_filtered:exists())

        ss._list_sessions()

        assert.are.same({ "empty.sess", "test.sess" }, ss._list_sessions())
        assert.truthy(test_sess:exists())
        assert.falsy(test_filtered:exists())
        assert.truthy(empty_sess:exists())
    end)
end)
