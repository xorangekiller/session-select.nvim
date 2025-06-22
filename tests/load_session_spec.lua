-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test loading sessions that have previously been saved.
describe("load_session", function()
    local Path = require("plenary.path")
    local stub = require("luassert.stub")
    local spy = require("luassert.spy")
    local ss = require("session-select")

    local scratch_dir = Path:new(vim.uv.cwd(), ".scratch")
    local test_sess = Path:new(scratch_dir, "test.sess")
    local test_filtered = Path:new(test_sess.filename .. ".tmpfiltered")
    local filterme_sess = Path:new(scratch_dir, "filterme.sess")
    local filterme_filtered = Path:new(filterme_sess.filename .. ".tmpfiltered")

    local stubs = {}

    -- Ensure that we start each test in a known state with a few saved
    -- sessions that may be loaded.
    before_each(function()
        scratch_dir:mkdir({ exists_ok = true })
        test_sess:write("let test = 1\necho \"Loaded test session.\"\n", "w")
        filterme_sess:write("let filterme = 1\n", "w")
        filterme_sess:write("nnoremap \\g \"zyiw:exe \"/\".@z.\"\"\n", "a")
        filterme_sess:write("echo \"Loaded filtered session.\"\n", "a")

        ss.setup({ storage_path = ".scratch" })
        ss.current_session = nil

        -- Mock all of the functions that load_session() may call that
        -- require user interaction. We need to provide alternatives to them.
        stubs = {
            select = stub.new(vim.ui, "select"),
            source = spy.on(ss, "_try_source"),
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

    it("load the session with the provided session name", function()
        assert.is_nil(ss.current_session)

        ss.load_session({ args = "test.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was.called()
        assert.equal("test.sess", ss.current_session)
    end)

    it("load the selected session", function()
        assert.is_nil(ss.current_session)

        stubs.select.invokes(function(contents, opts, callable)
            callable("test.sess")
        end)

        ss.load_session({})

        assert.stub(stubs.select).was.called()
        assert.stub(stubs.source).was.called()
        assert.equal("test.sess", ss.current_session)
    end)

    it("do not reload the current session", function()
        ss.current_session = "test.sess"

        ss.load_session({ args = "test.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was_not.called()
        assert.equal("test.sess", ss.current_session)
    end)

    it("reload the current session with a bang", function()
        ss.current_session = "test.sess"

        ss.load_session({ args = "test.sess", bang = true })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was.called()
        assert.equal("test.sess", ss.current_session)
    end)

    it("do not load the session if no session is selected", function()
        assert.is_nil(ss.current_session)

        stubs.select.invokes(function(contents, opts, callable)
            callable("")
        end)

        ss.load_session({})

        assert.stub(stubs.select).was.called()
        assert.stub(stubs.source).was_not.called()
        assert.is_nil(ss.current_session)
    end)

    it("do not select a session if the session directory does not exist", function()
        assert.is_nil(ss.current_session)

        scratch_dir:rm({ recursive = true })

        ss.load_session({})

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was_not.called()
        assert.is_nil(ss.current_session)
    end)

    it("do not load the provided session if it does not exist", function()
        assert.is_nil(ss.current_session)

        ss.load_session({ args = "missing.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was_not.called()
        assert.is_nil(ss.current_session)
    end)

    it("do not prompt to select a session if there are no sessions", function()
        assert.is_nil(ss.current_session)

        test_sess:rm()
        filterme_sess:rm()

        ss.load_session({})

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was_not.called()
        assert.is_nil(ss.current_session)
    end)

    it("load a session without filtering it at all", function()
        assert.is_nil(ss.current_session)

        for filter_option, filter_enabled in pairs(ss.options.filter) do
            assert.falsy(filter_enabled)
        end

        ss.load_session({ args = "filterme.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was.called_with(filterme_sess.filename)
        assert.equal("filterme.sess", ss.current_session)
        assert.falsy(filterme_filtered:exists())
    end)

    it("load a session with filters enabled, but nothing to filter out", function()
        assert.is_nil(ss.current_session)

        ss.options.filter.nomap = true

        ss.load_session({ args = "test.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was.called_with(test_sess.filename)
        assert.equal("test.sess", ss.current_session)
        assert.falsy(test_filtered:exists())
    end)

    it("load a session with key mappings filtered out", function()
        assert.is_nil(ss.current_session)

        ss.options.filter.nomap = true

        ss.load_session({ args = "filterme.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was.called_with(filterme_filtered.filename)
        assert.equal("filterme.sess", ss.current_session)
        assert.falsy(filterme_filtered:exists())
    end)

    it("delete temporary filter files even after errors", function()
        assert.is_nil(ss.current_session)

        ss.options.filter.nomap = true

        filterme_sess:write("error_not_a_real_function\n", "a")
        filterme_sess:write("echo \"We should never get this far.\"\n", "a")

        ss.load_session({ args = "filterme.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was.called_with(filterme_filtered.filename)
        assert.is_nil(ss.current_session)
        assert.falsy(filterme_filtered:exists())
    end)

    it("debug: load a session with no error handling", function()
        assert.is_nil(ss.current_session)

        ss.options.filter.nomap = true
        ss.options.debug.unconditional_source = true

        stubs.vim_source = spy.on(vim.cmd, "source")

        ss.load_session({ args = "filterme.sess" })

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was.called_with(filterme_filtered.filename)
        assert.stub(stubs.vim_source).was.called()
        assert.equal("filterme.sess", ss.current_session)
        assert.falsy(filterme_filtered:exists())
    end)

    it("debug: do not handle errors in sessions", function()
        assert.is_nil(ss.current_session)

        ss.options.filter.nomap = true
        ss.options.debug.unconditional_source = true

        filterme_sess:write("error_not_a_real_function\n", "a")
        filterme_sess:write("echo \"We should never get this far.\"\n", "a")

        stubs.vim_source = spy.on(vim.cmd, "source")

        assert.has.errors(function()
            ss.load_session({ args = "filterme.sess" })
        end)

        assert.stub(stubs.select).was_not.called()
        assert.stub(stubs.source).was.called_with(filterme_filtered.filename)
        assert.stub(stubs.vim_source).was.called()
        assert.is_nil(ss.current_session)
        assert.truthy(filterme_filtered:exists())
    end)
end)
