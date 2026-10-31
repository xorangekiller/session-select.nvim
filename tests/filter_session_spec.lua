-- Copyright (c) 2026 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test filtering of session file contents before they are sourced.
describe("filter_session", function()
    local Path = require("plenary.path")
    local ss = require("session-select")

    local scratch_dir = Path:new(vim.uv.cwd(), ".scratch", "filter")
    local session = Path:new(scratch_dir, "test.sess")

    local function read_file(path)
        local f = assert(io.open(path, "r"))
        local contents = f:read("*a")
        f:close()
        return contents
    end

    -- Filter the given session contents using the given filter configuration.
    --
    -- This is a helper function that makes it easier for these tests to call
    -- the internal session filtering function that we're testing with the
    -- given session `contents` and `filter` options (approximately as they
    -- would normally be supplied by the user in their configuration of this
    -- plugin).
    --
    -- Note: A nil filter uses the plugin defaults.
    --
    -- Returns the filtered contents, or nil if nothing was filtered.
    local function filter_contents(contents, filter)
        local opts = { storage_path = scratch_dir.filename }
        if filter ~= nil then
            opts.filter = filter
        end
        ss.setup(opts)

        session:write(contents, "w")
        local output = ss._filter_session(session.filename)
        if not output then
            return nil
        end

        local result = read_file(output)
        os.remove(output)
        return result
    end

    before_each(function()
        scratch_dir:mkdir({ parents = true, exists_ok = true })
    end)

    after_each(function()
        if scratch_dir:exists() then
            scratch_dir:rm({ recursive = true })
        end
    end)

    it("filter mapping commands with nomap", function()
        local result = filter_contents(
            'let test = 1\nnnoremap x y\nnmap <F2> :foo<CR>\necho "ok"\n',
            { nomap = true, options = false }
        )

        assert.truthy(result)
        assert.falsy(result:find("nnoremap", 1, true))
        assert.falsy(result:find("nmap", 1, true))
        assert.truthy(result:find("let test = 1", 1, true))
        assert.truthy(result:find('echo "ok"', 1, true))
    end)

    it("filter default global option assignments", function()
        local result = filter_contents([[
let test = 1
set runtimepath=/tmp/rtp
set packpath=/tmp/pp
set noloadplugins
set sessionoptions=blank,buffers
set statusline=OLD
set tabline=OLD
set listchars=tab:>-
set window=65
set list
set nolist
set number
set nonumber
set tabstop=4
setlocal statusline=LOCAL
set path=.,/tmp
echo "done"
]])

        assert.truthy(result)
        for _, name in ipairs({
            "runtimepath",
            "packpath",
            "loadplugins",
            "sessionoptions",
            "statusline",
            "tabline",
            "listchars",
            "window",
            "tabstop",
        }) do
            assert.falsy(result:find("set .*" .. name, 1, false))
        end
        assert.falsy(result:find("set list", 1, true))
        assert.falsy(result:find("set nolist", 1, true))
        assert.falsy(result:find("set number", 1, true))
        assert.falsy(result:find("set nonumber", 1, true))
        assert.truthy(result:find("setlocal statusline=LOCAL", 1, true))
        assert.truthy(result:find("set path=.,/tmp", 1, true))
        assert.truthy(result:find("let test = 1", 1, true))
    end)

    it("filter mappings and options together", function()
        local result = filter_contents(
            "nnoremap x y\nset statusline=OLD\nset path=.,/tmp\n",
            { nomap = true }
        )

        assert.truthy(result)
        assert.falsy(result:find("nnoremap", 1, true))
        assert.falsy(result:find("statusline", 1, true))
        assert.truthy(result:find("set path=.,/tmp", 1, true))
    end)

    it("add option names to the defaults", function()
        local result = filter_contents(
            "set statusline=OLD\nset path=.,/tmp\nset tabline=OLD\n",
            { options = { add = { "path" } } }
        )

        assert.truthy(result)
        assert.falsy(result:find("statusline", 1, true))
        assert.falsy(result:find("tabline", 1, true))
        assert.falsy(result:find("path", 1, true))
    end)

    it("remove option names from the defaults", function()
        local result = filter_contents(
            "set statusline=OLD\nset runtimepath=/tmp/rtp\n",
            { options = { remove = { "statusline" } } }
        )

        assert.truthy(result)
        assert.truthy(result:find("set statusline=OLD", 1, true))
        assert.falsy(result:find("runtimepath", 1, true))
    end)

    it("replace the defaults with an explicit list", function()
        local result = filter_contents(
            "set runtimepath=/tmp/rtp\nset statusline=OLD\n",
            { options = { replace = { "runtimepath" } } }
        )

        assert.truthy(result)
        assert.falsy(result:find("runtimepath", 1, true))
        assert.truthy(result:find("set statusline=OLD", 1, true))
    end)

    it("apply replace, remove, then add in order", function()
        local result = filter_contents(
            "set runtimepath=/tmp/rtp\nset statusline=OLD\nset path=.,/tmp\n",
            {
                options = {
                    replace = { "runtimepath", "statusline" },
                    remove = { "statusline" },
                    add = { "path" },
                },
            }
        )

        assert.truthy(result)
        assert.falsy(result:find("runtimepath", 1, true))
        assert.truthy(result:find("set statusline=OLD", 1, true))
        assert.falsy(result:find("path", 1, true))
    end)

    it("recognize short option aliases in custom lists", function()
        local result = filter_contents(
            "set runtimepath=/tmp/rtp\nset statuscolumn=OLD\nset tabline=OLD\n",
            { options = { replace = { "rtp", "stc" } } }
        )

        assert.truthy(result)
        assert.falsy(result:find("runtimepath", 1, true))
        assert.falsy(result:find("statuscolumn", 1, true))
        assert.truthy(result:find("set tabline=OLD", 1, true))
    end)

    it("preserve unfiltered options on a shared set line", function()
        local result = filter_contents(
            "set statusline=OLD runtimepath=/tmp/rtp tabline=OLD\n",
            { options = { replace = { "statusline", "tabline" } } }
        )

        assert.equal("set runtimepath=/tmp/rtp\n", result)
    end)

    it("preserve escaped spaces in unfiltered set values", function()
        local result = filter_contents(
            "set grepprg=rg\\ --vimgrep\\ --smart-case statusline=OLD\n",
            { options = { replace = { "statusline" } } }
        )

        assert.equal(
            "set grepprg=rg\\ --vimgrep\\ --smart-case\n",
            result
        )
    end)

    it("filter let &g: and let & global option assignments", function()
        local result = filter_contents([[
let &g:statusline = 'OLD'
let &statusline = 'OLD'
let &l:statusline = 'LOCAL'
let &g:tabline = 'OLD'
let &g:ignorecase = 1
]])

        assert.truthy(result)
        assert.falsy(result:find("&g:statusline", 1, true))
        assert.falsy(result:find("&statusline", 1, true))
        assert.truthy(result:find("&l:statusline", 1, true))
        assert.falsy(result:find("&g:tabline", 1, true))
        assert.truthy(result:find("&g:ignorecase", 1, true))
    end)

    it("filter unknown option assignments", function()
        local result = filter_contents([[
set nosuchoptionxyz=1
set nonosuchoptionxyz
set invnosuchoptionxyz
set path=.,/tmp nosuchoptionxyz=1
setlocal nosuchoptionxyz=1
setlocal tabstop=4
let &g:nosuchoptionxyz = 1
let &l:nosuchoptionxyz = 1
let &l:tabstop = 8
set t_Co=256
]])

        assert.truthy(result)
        assert.falsy(result:find("nosuchoptionxyz", 1, true))
        assert.truthy(result:find("set path=.,/tmp", 1, true))
        assert.truthy(result:find("setlocal tabstop=4", 1, true))
        assert.truthy(result:find("let &l:tabstop = 8", 1, true))
        assert.truthy(result:find("set t_Co=256", 1, true))
    end)

    it("leave unknown option assignments alone when filtering is disabled", function()
        assert.is_nil(
            filter_contents("set nosuchoptionxyz=1\n", { options = false })
        )
    end)

    it("drop directory changes to missing directories", function()
        local cwd = vim.fs.normalize(vim.uv.cwd())
        local result = filter_contents(table.concat({
            "cd /nonexistent/session/dir",
            "chdir /nonexistent/session/dir",
            "lcd /nonexistent/session/dir",
            "tcd /nonexistent/session/dir",
            "cd " .. cwd,
            "",
        }, "\n"))

        assert.truthy(result)
        assert.falsy(result:find("nonexistent", 1, true))
        assert.truthy(result:find("cd " .. cwd, 1, true))
    end)

    it("handle escaped spaces in directory changes", function()
        local dir = vim.fs.normalize(vim.uv.cwd()) .. "/.scratch/filter/with space"
        vim.fn.mkdir(dir, "p")
        local escaped = dir:gsub(" ", "\\ ")

        assert.is_nil(filter_contents("cd " .. escaped .. "\n"))
    end)

    it("do not filter session mechanics options", function()
        local contents = table.concat({
            "set cpo&vim",
            "set shortmess=ltToOCF",
            "set winheight=1 winwidth=20",
            "set hlsearch",
            "let &g:so = s:so_save",
            "",
        }, "\n")

        assert.is_nil(filter_contents(contents))
    end)

    it("do not write a file when nothing matches", function()
        assert.is_nil(filter_contents("let test = 1\n"))
        assert.falsy(Path:new(session.filename .. ".tmpfiltered"):exists())
    end)

    it("filter nothing when filter is an empty table", function()
        assert.is_nil(
            filter_contents("nnoremap x y\nset statusline=OLD\n", {})
        )
    end)

    it("leave option assignments alone when option filtering is disabled", function()
        assert.is_nil(
            filter_contents("set statusline=OLD\n", { options = false })
        )
    end)
end)
