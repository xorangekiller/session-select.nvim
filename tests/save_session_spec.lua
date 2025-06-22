-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test saving the current session to disk.
describe("save_sesssion", function()
    local Path = require("plenary.path")
    local stub = require("luassert.stub")
    local spy = require("luassert.spy")
    local ss = require("session-select")

    local stubs = {}

    function reset_session()
        scratch_dir = Path:new(vim.uv.cwd(), ".scratch")
        if scratch_dir:exists() then
            scratch_dir:rm({ recursive = true })
        end
        ss.current_session = nil
    end

    -- Ensure that we start each test in a clean state with no saved sessions.
    before_each(function()
        ss.setup({ storage_path = ".scratch" })
        reset_session()

        -- Mock all of the functions that save_session() may call that require
        -- user interaction. We need to provide alternatives to them.
        stubs = {
            input = stub.new(vim.fn, "input"),
            confirm = stub.new(vim.fn, "confirm"),
            mksession = spy.on(vim.cmd, "mksession"),
        }
    end)

    -- Ensure that we deleted any saved sessions after each test so that we
    -- don't interfere with other test cases.
    after_each(function()
        reset_session()

        for _, stubbed_func in pairs(stubs) do
            stubbed_func:revert()
        end
        stubs = {}
    end)

    it("save a new session with a provided session name", function()
        assert.is_nil(ss.current_session)
        assert.are.same({}, ss._list_sessions())

        ss.save_session({ args = "test.sess" })

        assert.stub(stubs.input).was_not.called()
        assert.stub(stubs.confirm).was_not.called()
        assert.stub(stubs.mksession).was.called()
        assert.truthy(vim.uv.fs_stat(".scratch/test.sess"))
        assert.equal("test.sess", ss.current_session)
        assert.are.same({ "test.sess" }, ss._list_sessions())
    end)

    it("don't save if no session name is entered in the prompt", function()
        assert.is_nil(ss.current_session)
        assert.are.same({}, ss._list_sessions())

        ss.save_session({})

        assert.stub(stubs.input).was.called()
        assert.stub(stubs.confirm).was_not.called()
        assert.stub(stubs.mksession).was_not.called()
        assert.falsy(vim.uv.fs_stat(".scratch"))
        assert.is_nil(ss.current_session)
        assert.are.same({}, ss._list_sessions())
    end)

    it("don't save with an empty session name", function()
        stubs.input.returns("")
        assert.is_nil(ss.current_session)
        assert.are.same({}, ss._list_sessions())

        ss.save_session({ args = "" })

        assert.stub(stubs.input).was.called()
        assert.stub(stubs.confirm).was_not.called()
        assert.stub(stubs.mksession).was_not.called()
        assert.falsy(vim.uv.fs_stat(".scratch"))
        assert.is_nil(ss.current_session)
        assert.are.same({}, ss._list_sessions())
    end)

    it("prompt for a session name for the session to save", function()
        stubs.input.returns("test.sess")
        assert.is_nil(ss.current_session)
        assert.are.same({}, ss._list_sessions())

        ss.save_session({})

        assert.stub(stubs.input).was.called()
        assert.stub(stubs.confirm).was_not.called()
        assert.stub(stubs.mksession).was.called()
        assert.truthy(vim.uv.fs_stat(".scratch/test.sess"))
        assert.equal("test.sess", ss.current_session)
        assert.are.same({ "test.sess" }, ss._list_sessions())
    end)

    it("prompt to overwrite an existing named session", function()
        Path:new(".scratch"):mkdir()
        Path:new(".scratch/test.sess"):write("set test = 1\n", "w")

        stubs.confirm.returns(1)
        assert.is_nil(ss.current_session)
        assert.are.same({ "test.sess" }, ss._list_sessions())

        ss.save_session({ args = "test.sess" })

        assert.stub(stubs.input).was_not.called()
        assert.stub(stubs.confirm).was.called()
        assert.stub(stubs.mksession).was.called()
        assert.truthy(vim.uv.fs_stat(".scratch/test.sess"))
        assert.equal("test.sess", ss.current_session)
        assert.are.same({ "test.sess" }, ss._list_sessions())
    end)

    it("prompt to overwrite the current session", function()
        Path:new(".scratch"):mkdir()
        Path:new(".scratch/test.sess"):write("set test = 1\n", "w")

        stubs.confirm.returns(1)
        ss.current_session = "test.sess"
        assert.are.same({ "test.sess" }, ss._list_sessions())

        ss.save_session({})

        assert.stub(stubs.input).was_not.called()
        assert.stub(stubs.confirm).was.called()
        assert.stub(stubs.mksession).was.called()
        assert.truthy(vim.uv.fs_stat(".scratch/test.sess"))
        assert.equal("test.sess", ss.current_session)
        assert.are.same({ "test.sess" }, ss._list_sessions())
    end)

    it("do not overwrite an existing session if not confirmed", function()
        Path:new(".scratch"):mkdir()
        Path:new(".scratch/test.sess"):write("set test = 1\n", "w")

        stubs.confirm.returns(2)
        ss.current_session = "test.sess"
        assert.are.same({ "test.sess" }, ss._list_sessions())

        ss.save_session({})

        assert.stub(stubs.input).was_not.called()
        assert.stub(stubs.confirm).was.called()
        assert.stub(stubs.mksession).was_not.called()
        assert.truthy(vim.uv.fs_stat(".scratch/test.sess"))
        assert.equal("test.sess", ss.current_session)
        assert.are.same({ "test.sess" }, ss._list_sessions())
    end)

    it("overwrite the current session without asking with a bang", function()
        Path:new(".scratch"):mkdir()
        Path:new(".scratch/test.sess"):write("set test = 1\n", "w")

        ss.current_session = "test.sess"
        assert.are.same({ "test.sess" }, ss._list_sessions())

        ss.save_session({ bang = true })

        assert.stub(stubs.input).was_not.called()
        assert.stub(stubs.confirm).was_not.called()
        assert.stub(stubs.mksession).was.called()
        assert.truthy(vim.uv.fs_stat(".scratch/test.sess"))
        assert.equal("test.sess", ss.current_session)
        assert.are.same({ "test.sess" }, ss._list_sessions())
    end)
end)
