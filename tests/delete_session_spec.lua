-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test deleting sessions that have previously been saved.
describe("delete_session", function()
    local Path = require("plenary.path")
    local stub = require("luassert.stub")
    local ss = require("session-select")

    local scratch_dir = Path:new(vim.uv.cwd(), ".scratch")
    local test_sess = Path:new(scratch_dir, "test.sess")
    local empty_sess = Path:new(scratch_dir, "empty.sess")

    local stubs = {}

    -- Ensure that we start each test in a known state with a few saved
    -- sessions that may be deleted.
    before_each(function()
        scratch_dir:mkdir({ exists_ok = true })
        test_sess:write("set test = 1\n", "w")
        empty_sess:write("", "w")

        ss.setup({ storage_path = ".scratch" })
        ss.current_session = nil

        -- Mock all of the functions that delete_session() may call that
        -- require user interaction. We need to provide alternatives to them.
        stubs = {
            select = stub.new(vim.ui, "select"),
            confirm = stub.new(vim.fn, "confirm"),
        }
    end)

    -- Ensure that we reset to a known good state after each test case.
    after_each(function()
        if scratch_dir:exists() then
            scratch_dir:rm({ recursive = true })
        end

        for _, stubbed_func in pairs(stubs) do
            stubbed_func:revert()
        end
        stubs = {}
    end)

    it("delete the session with the provided session name", function()
        stubs.confirm.returns(1)

        ss.delete_session({ args = "test.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.confirm).was.called()
        assert.falsy(test_sess:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("delete the selected session", function()
        stubs.select.invokes(function(contents, opts, callable)
            callable("test.sess")
        end)
        stubs.confirm.returns(1)

        ss.delete_session({})

        assert.stub(stubs.select).was.called()
        assert.stub(stubs.confirm).was.called()
        assert.falsy(test_sess:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("delete the current session", function()
        stubs.confirm.returns(1)
        ss.current_session = "test.sess"

        ss.delete_session({ args = "test.sess" })

        assert.is_nil(ss.current_session)
        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.confirm).was.called()
        assert.falsy(test_sess:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("deleting another session does not affect the current session", function()
        stubs.confirm.returns(1)
        ss.current_session = "empty.sess"

        ss.delete_session({ args = "test.sess" })

        assert.equal("empty.sess", ss.current_session)
        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.confirm).was.called()
        assert.falsy(test_sess:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("do not delete the session if no session is selected", function()
        stubs.select.invokes(function(contents, opts, callable)
            callable("")
        end)

        ss.delete_session({})

        assert.stub(stubs.select).was.called()
        assert.stub(stubs.confirm).was_not.called()
        assert.truthy(test_sess:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("do not delete the provided session if it does not exist", function()
        ss.delete_session({ args = "missing.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.confirm).was_not.called()
        assert.truthy(test_sess:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("do not select a session if the session directory does not exist", function()
        scratch_dir:rm({ recursive = true })
        assert.falsy(scratch_dir:exists())

        ss.delete_session({})

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.confirm).was_not.called()
    end)

    it("do not prompt to select a session if there are no sessions", function()
        test_sess:rm()
        empty_sess:rm()
        assert.are.same({}, ss._list_sessions())

        ss.delete_session({})

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.confirm).was_not.called()
    end)

    it("do not delete the session if it is not confirmed", function()
        stubs.confirm.returns(2)

        ss.delete_session({ args = "test.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.confirm).was.called()
        assert.truthy(test_sess:exists())
        assert.truthy(empty_sess:exists())
    end)

    it("do not prompt to delete a session with a bang", function()
        ss.delete_session({ args = "test.sess", bang = true })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.confirm).was_not.called()
        assert.falsy(test_sess:exists())
        assert.truthy(empty_sess:exists())
    end)
end)
