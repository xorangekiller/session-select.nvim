-- Copyright (c) 2025-2026 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

local M = {
    -- global options that are typically owned by Neovim, the user's
    -- configuration, or plugins and therefore should not be restored from a
    -- session file
    default_filter_options = {
        -- plugin/runtime environment
        "runtimepath",
        "packpath",
        "loadplugins",
        -- session/state persistence
        "sessionoptions",
        "shada",
        "shadafile",
        -- UI chrome
        "statusline",
        "tabline",
        "winbar",
        "statuscolumn",
        "laststatus",
        "showtabline",
        "cmdheight",
        "listchars",
        -- appearance/GUI
        "termguicolors",
        "background",
        "guifont",
        "guifontwide",
        -- terminal/window sizing
        "window",
        -- global defaults for local editing options
        "list",
        "number",
        "tabstop",
        -- user interaction
        "clipboard",
        "mouse",
        "helplang",
        -- shell/environment
        "shell",
        "shellcmdflag",
        "shellpipe",
        "shellquote",
        "shellredir",
        "shellslash",
        "shellxquote",
        "shellxescape",
        -- external tools
        "makeprg",
        "errorformat",
        "grepprg",
        "grepformat",
        -- completion/wildcards
        "completeopt",
        "wildignore",
        "wildoptions",
        "wildignorecase",
        -- paths
        "undodir",
        "backupdir",
        "backupskip",
        "directory",
        "viewdir",
        "spellfile",
        -- encodings
        "encoding",
        "fileformats",
        "fileencodings",
    },
    -- default configuration options for this plugin
    defaults = {
        -- directory where sessions are stored
        storage_path = vim.fs.normalize(vim.fn.stdpath("data") .. "/sessions"),
        -- automatically register the commands for this plugin?
        register_commands = true,
        -- wipe all buffers/windows from the current session before loading
        -- another session (prompts to save/discard unsaved changes)
        wipe_before_load = true,
        -- show a preview of the session file in pickers that support
        -- vim.ui.select()'s preview_item callback
        preview = true,
        -- options to allow filtering things out of existing sessions that are
        -- loaded (set to {} to disable filtering entirely)
        filter = {
            -- filter key mapping commands out of the session before loading it
            -- (which is particularly helpful if you have existing sessions
            -- that contain keybindings from plugins that you have since
            -- removed from your config)
            nomap = false,
            -- filter global option assignments out of the session before
            -- loading it (true = use the built-in list, false = disable, or a
            -- table with replace/add/remove lists)
            options = true,
        },
        -- options that should only be set by developers who are working on and
        -- debugging this module
        debug = {
            -- use our own internal implementation of the joinpath() function,
            -- even if we have a new enough version of Neovim that we don't
            -- need it (intended primarily for unit testing)
            joinpath_compat = false,
            -- don't try to catch errors encountered while sourcing sessions,
            -- which means that temporary filtered session files will not be
            -- cleaned up (and may be investigated later)
            unconditional_source = false,
        },
    },
    -- current options configured by the user for this plugin when it was setup
    options = {},
    -- session that was last loaded or saved by the user
    current_session = nil,
}

-- Configure this plugin using the provided options.
--
-- Typically this function will be called by your package manager. It must be
-- called before any other functions in this module.
function M.setup(opts)
    opts = opts or {}

    -- Deep copy the defaults so that nested tables cannot be shared with and
    -- mutated by the user's configuration (or by tests).
    M.options = vim.tbl_deep_extend(
        "force",
        {},
        vim.deepcopy(M.defaults),
        opts
    )

    -- Keep filter = {} (and any non-table filter value) working as an explicit
    -- request to disable all filtering. Other partial filter tables are merged
    -- with the defaults normally.
    if type(M.options.filter) ~= "table" then
        M.options.filter = { nomap = false, options = false }
    elseif opts.filter ~= nil
        and type(opts.filter) == "table"
        and next(opts.filter) == nil
    then
        M.options.filter = { nomap = false, options = false }
    end

    -- Ensure that our storage path is absolute. That will ensure that if the
    -- user changes directories later before saving, the storage path will
    -- still remain the same as it was intended to be when it was setup,
    -- relative to what it was when this plugin was setup.
    M.options.storage_path = vim.fn.fnamemodify(M.options.storage_path, ":p")

    if M.options.register_commands then
        M.register_commands()
    end
end

-- Register the commands for this function.
--
-- These commands are how the user interacts with this plugin. You should
-- register them by default most of the time, unless you really want to change
-- the name of the commands by registering them yourself. That would be an
-- advanced use-case.
function M.register_commands()
    vim.api.nvim_create_user_command("SaveSession", M.save_session, {
        nargs = "?",
        bang = true, -- Overwrite an existing session without asking.
        complete = M._complete_session,
    })
    vim.api.nvim_create_user_command("LoadSession", M.load_session, {
        nargs = "?",
        bang = true, -- Always load the given session even if it is already loaded.
        complete = M._complete_session,
    })
    vim.api.nvim_create_user_command("DeleteSession", M.delete_session, {
        nargs = "?",
        bang = true, -- Delete the given session without asking.
        complete = M._complete_session,
    })
end

-- Do we need to use our compatibility layer for joinpath() (true), or can we
-- use Neovim's builtin vim.fs.joinpath() function (false)?
function M._need_joinpath_compat()
    if M.options and M.options.debug and M.options.debug.joinpath_compat then
        return true
    end
    return (vim.fn.has("nvim-0.10.0") ~= 1)
end

-- Join the given paths into a single path.
--
-- This function emulates vim.fs.joinpath() on Neovim versions prior to 0.10.0.
-- It can be safely removed once we no longer care about supporting earlier
-- versions.
--
-- Note: This is an internal helper function. It should not be called outside
-- of this module.
function M._joinpath(...)
    if not M._need_joinpath_compat() then
        return vim.fs.joinpath(...)
    end

    if select("#", ...) == 0 then
        return ""
    end

    -- Collect the arguments into a table so that we can iterate over them.
    local args = {...}

    local path = ""
    for i, arg in ipairs(args) do
        if i == 1 or not path then
            path = arg
        else
            path = path .. "/" .. arg
        end
    end
    return vim.fs.normalize(path)
end

-- Return a list of all of the sessions that have been saved.
function M._list_sessions()
    if not vim.uv.fs_stat(M.options.storage_path) then
        return {}
    end

    local contents = {}
    for entry in vim.fs.dir(M.options.storage_path) do
        local entry_path = M._joinpath(M.options.storage_path, entry)
        local entry_stat
        if entry ~= "" and entry_path and entry_path ~= "" then
            entry_stat = vim.uv.fs_lstat(entry_path)
        end

        if not entry_stat or entry_stat.type ~= "file" then
            -- Skip any entries that are not files. We don't need to do
            -- anything here.
        elseif entry:find(".tmpfiltered$") then
            -- In theory, we should never have an temporary filtered sessions
            -- in our session storage directory because they were previously
            -- cleaned up. However, if the plugin errored out while loading a
            -- session, it may. Silently clean them up now rather than showing
            -- them to the user.
            os.remove(entry_path)
        else
            table.insert(contents, entry)
        end
    end

    -- Technically it isn't necessary to sort the list of sessions, but it
    -- makes them more pleasing to look at. Otherwise they would always be
    -- listed in the order that they were read from the filesystem, which isn't
    -- guaranteed to be consistent each time.
    table.sort(contents)

    return contents
end

-- Return the saved session names that start with the given prefix.
--
-- This is used as the completion callback for the commands. Completion
-- callbacks must not raise errors, so a failure to read the session directory
-- simply produces no candidates.
function M._complete_session(arg_lead)
    local ok, sessions = pcall(M._list_sessions)
    if not ok then
        return {}
    end

    local ignore_case = vim.o.wildignorecase
    local lead = ignore_case and arg_lead:lower() or arg_lead
    local matches = {}
    for _, name in ipairs(sessions) do
        local candidate = ignore_case and name:lower() or name
        if candidate:sub(1, #lead) == lead then
            table.insert(matches, name)
        end
    end

    return matches
end

-- Return a buffer containing the raw contents of the given session file.
--
-- This is used as the preview_item callback for vim.ui.select(). Pickers that
-- do not support previews simply ignore the returned table. A single buffer is
-- reused for all previews so that pickers which read (but never display) the
-- buffer do not accumulate one scratch buffer per preview request.
function M._preview_session(name)
    local path = M._joinpath(M.options.storage_path, vim.fs.basename(name))

    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        lines = { "unable to read session: " .. path }
    end

    local buf = M._preview_buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_create_buf(false, true)
        M._preview_buf = buf
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].swapfile = false
        vim.bo[buf].filetype = "vim"
        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = buf,
            once = true,
            callback = function()
                if M._preview_buf == buf then
                    M._preview_buf = nil
                end
            end,
        })
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    return { buf = buf }
end

-- Build the options for a session selection picker.
function M._selection_options(prompt)
    local opts = { prompt = prompt }
    if M.options.preview then
        opts.preview_item = M._preview_session
    end
    return opts
end

-- Save the current session with the given name, and set it as our current
-- session so that the name may be omitted the next time we save.
function M.save_session(params)
    local name
    if params.args and params.args ~= "" then
        name = params.args
    elseif M.current_session then
        name = M.current_session
    else
        name = vim.fn.input("name: ")
        -- The Vim input() function doesn't print a newline after the user
        -- presses enter. That technically doesn't really affect anything, but
        -- it makes anything that we print after that run into it, which looks
        -- weird. Printing a newline preemptively makes it look better.
        print("\n")
    end

    if name and name ~= "" then
        name = vim.fs.basename(name)
        local path = M._joinpath(M.options.storage_path, name)

        -- Create the directory to save the sessions if it doesn't already
        -- exist.
        if not vim.uv.fs_stat(M.options.storage_path) then
            vim.fn.mkdir(M.options.storage_path)
        end

        if next(vim.fs.find(name, { path = M.options.storage_path })) == nil then
            vim.cmd.mksession({ args = { path } })
            M.current_session = name
            print("session saved: " .. path .. "\n")
        else
            local confirm = 1
            if not params.bang then
                confirm = vim.fn.confirm(
                    "overwrite session (" .. name .. ")?",
                    "&Yes\n&No",
                    2
                )
            end
            if confirm == 1 then
                vim.cmd.mksession({
                    args = { path },
                    bang = true,
                })
                M.current_session = name
                print("session updated: " .. path .. "\n")
            else
                print("session not updated\n")
            end
        end
    else
        print("no session written\n")
    end
end

-- Return the canonical name of the given option, or the lowercased name if
-- Neovim cannot resolve it (which may happen for options that are newer than
-- the running Neovim version).
function M._canonical_option_name(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local ok, info = pcall(vim.api.nvim_get_option_info, name)
    if ok
        and type(info) == "table"
        and type(info.name) == "string"
        and info.name ~= ""
    then
        return info.name
    end

    return name:lower()
end

-- Is the given option name in the set of options that we are filtering out?
function M._option_name_is_filtered(name, filtered)
    local lower = name:lower()
    if filtered[lower] then
        return true
    end

    local canonical = M._canonical_option_name(name)
    return canonical ~= nil and filtered[canonical] == true
end

-- Does the given option exist in this version of Neovim?
--
-- Note: vim.api.nvim_get_option_info() cannot resolve terminal ("t_") options,
-- but exists("&t_Co") can, so use exists() here instead.
function M._option_is_known(name)
    if type(name) ~= "string" or name == "" then
        return false
    end

    local lower = name:lower()
    if lower == "all" or lower == "termcap" then
        return true
    end

    return vim.fn.exists("&" .. name) == 1
end

-- Is the given `:set` token setting an option that does not exist in this
-- version of Neovim (for example, an option from a newer version or from a
-- plugin/feature that is not loaded)?
function M._set_token_is_unsupported(token)
    local name = token:match("^([%a][%w_]*)")
    if not name then
        return false
    end

    if M._option_is_known(name) then
        return false
    end

    local lower = name:lower()
    if lower:sub(1, 2) == "no" and #name > 2 then
        return not M._option_is_known(name:sub(3))
    elseif lower:sub(1, 3) == "inv" and #name > 3 then
        return not M._option_is_known(name:sub(4))
    end

    return true
end

-- Is the given `:set` token setting an option that we are filtering out?
function M._set_token_is_filtered(token, filtered)
    local name = token:match("^([%a][%w_]*)")
    if not name then
        return false
    end

    if M._option_name_is_filtered(name, filtered) then
        return true
    end

    local lower = name:lower()
    if lower:sub(1, 2) == "no" and #lower > 2 then
        return M._option_name_is_filtered(lower:sub(3), filtered)
    elseif lower:sub(1, 3) == "inv" and #lower > 3 then
        return M._option_name_is_filtered(lower:sub(4), filtered)
    end

    return false
end

-- Split the argument string of a `:set` command on unescaped whitespace while
-- preserving backslash escapes so that values containing spaces remain valid.
function M._split_set_args(args)
    local tokens = {}
    local current = {}
    local escaped = false
    for i = 1, #args do
        local char = args:sub(i, i)
        if escaped then
            table.insert(current, char)
            escaped = false
        elseif char == "\\" then
            table.insert(current, char)
            escaped = true
        elseif char:match("%s") then
            if #current > 0 then
                table.insert(tokens, table.concat(current))
                current = {}
            end
        else
            table.insert(current, char)
        end
    end

    if #current > 0 then
        table.insert(tokens, table.concat(current))
    end

    return tokens
end

-- Expand a possibly escaped file name from a session file into a path that
-- can be checked on disk.
function M._session_path(path)
    local unescaped = path:gsub("\\(.)", "%1")
    return vim.fn.fnamemodify(unescaped, ":p")
end

-- Is the given line a directory-changing command whose target does not exist
-- (or is not a directory)?
function M._is_missing_dir_command(line)
    local command, target = line:match("^%s*([%a]+)%s+(.+)$")
    if not command then
        return false
    end

    command = command:lower()
    if
        command ~= "cd"
        and command ~= "chdir"
        and command ~= "tcd"
        and command ~= "tchdir"
        and command ~= "lcd"
        and command ~= "lchdir"
    then
        return false
    end

    -- Don't try to interpret targets that may be Vim filename modifiers or
    -- environment variable expansions rather than literal paths. Such lines
    -- are rare in session files (mksession writes expanded paths), and leaving
    -- them alone is safer than dropping a valid directory change.
    if target:find("[%%$#<]") then
        return false
    end

    local stat = vim.uv.fs_stat(M._session_path(target))
    return not stat or stat.type ~= "directory"
end

-- Filter option assignments out of a single session file line.
--
-- When `filtered` contains option names, global assignments to those options
-- are removed. When `drop_unknown` is true, assignments to options that do not
-- exist in this version of Neovim are removed from any of the `:set` variants
-- (global or local).
--
-- Returns the new line, or nil if the whole line should be removed.
function M._filter_option_line(line, filtered, drop_unknown)
    local command, args = line:match("^%s*(setlocal)%s+(.+)$")
    if not command then
        command, args = line:match("^%s*(setl)%s+(.+)$")
    end
    if not command then
        command, args = line:match("^%s*(setglobal)%s+(.+)$")
    end
    if not command then
        command, args = line:match("^%s*(setg)%s+(.+)$")
    end
    if not command then
        command, args = line:match("^%s*(set)%s+(.+)$")
    end
    if not command then
        command, args = line:match("^%s*(se)%s+(.+)$")
    end

    if command then
        local is_global = command == "set"
            or command == "se"
            or command == "setglobal"
            or command == "setg"
        local tokens = M._split_set_args(args)
        local kept = {}
        for _, token in ipairs(tokens) do
            local drop = (is_global and M._set_token_is_filtered(token, filtered))
                or (drop_unknown and M._set_token_is_unsupported(token))
            if not drop then
                table.insert(kept, token)
            end
        end

        if #kept == 0 then
            return nil
        elseif #kept == #tokens then
            return line
        end

        return command .. " " .. table.concat(kept, " ")
    end

    local let_scope, let_option =
        line:match("^%s*let%s+&([gl]):([%a][%w_]*)%s*=")
    if not let_option then
        let_option = line:match("^%s*let%s+&([%a][%w_]*)%s*=")
        if let_option then
            let_scope = "g"
        end
    end

    if let_option then
        if
            let_scope == "g"
            and M._option_name_is_filtered(let_option, filtered)
        then
            return nil
        end

        if drop_unknown and not M._option_is_known(let_option) then
            return nil
        end
    end

    return line
end

-- Resolve the configured option filter into a set of option names.
--
-- The filter options are designed to be user-friendly, which unfortunately
-- means they're a bit complex for us to deal with. I think that's
-- fundamentally a good trade-off, but it means that we need to resolve them
-- into a canonical list of options that we should filter out at some point
-- while loading a session file. That's what this internal helper function
-- does. It understands the true/false syntax for our configured filter
-- options, knows when to use the defaults versus the user's replacement
-- options, and can apply the add/remove lists to it.
--
-- Returns the canonical list of options to filter out of the session file
-- before loading it.
function M._option_filter_set()
    local configured = M.options
        and M.options.filter
        and M.options.filter.options

    if configured == true then
        configured = { replace = M.default_filter_options }
    elseif type(configured) ~= "table" then
        return {}
    end

    local names = {}
    local seen = {}
    local function add_names(list)
        if type(list) ~= "table" then
            return
        end

        for _, name in ipairs(list) do
            if type(name) == "string" and name ~= "" then
                local canonical = M._canonical_option_name(name)
                if canonical and not seen[canonical] then
                    seen[canonical] = true
                    table.insert(names, name)
                end
            end
        end
    end

    local base = configured.replace
    if type(base) ~= "table" then
        base = M.default_filter_options
    end
    add_names(base)

    local removals = {}
    if type(configured.remove) == "table" then
        for _, name in ipairs(configured.remove) do
            local canonical = M._canonical_option_name(name)
            if canonical then
                removals[canonical] = true
            end
        end
    end

    if next(removals) then
        for i = #names, 1, -1 do
            local canonical = M._canonical_option_name(names[i])
            if canonical and removals[canonical] then
                table.remove(names, i)
                seen[canonical] = nil
            end
        end
    end

    add_names(configured.add)

    local filtered = {}
    for _, name in ipairs(names) do
        filtered[name:lower()] = true
        local canonical = M._canonical_option_name(name)
        if canonical then
            filtered[canonical] = true
        end
    end

    return filtered
end

-- Read the given session file, and filter out anything that we're configured
-- to remove (or anything that we know will fail to load cleanly).
--
-- Note: This is a helper function, not a command. Users of this plugin are not
-- expected to call it directly.
--
-- Returns: If anything was filtered out of the session file, the path of the
-- new filtered session file is returned. The caller is responsible for
-- removing it once it has been loaded. If nothing needed to be removed from
-- the session file, then nil is returned.
function M._filter_session(input)
    -- Shortcut: Don't bother reading the input file at all if there is nothing
    -- that we could possibly need to filter out.

    if not M.options or not M.options.filter then
        return nil
    end

    local nomap = M.options.filter.nomap and true or false
    local option_filter = M._option_filter_set()
    local filter_options = next(option_filter) ~= nil
    -- Unknown options are part of the option filtering feature. They are
    -- always dropped when that feature is enabled (the default), even if the
    -- configured option list itself is empty.
    local prune_unknown = M.options.filter.options ~= false
    -- Removing directory changes (e.g. cd, tcd) to paths that do not exist is
    -- part of making session loading more fault-tolerant, so it is independent
    -- of the filter configuration. We need to enable it separately.
    local harden = not (M.options.debug and M.options.debug.unconditional_source)

    if
        not nomap
        and not filter_options
        and not prune_unknown
        and not harden
    then
        return nil
    end

    -- Read the session file and filter out anything that we were asked to.

    local f_in = io.open(input, "r")
    if not f_in then
        return nil
    end

    local outlines = {}
    local filtered = false
    for line in f_in:lines() do
        local keep = true
        if nomap and line:find("^%a+map") then
            keep = false
        else
            local filtered_line = line
            if harden and M._is_missing_dir_command(filtered_line) then
                filtered_line = nil
            elseif filter_options or prune_unknown then
                filtered_line = M._filter_option_line(
                    filtered_line,
                    option_filter,
                    prune_unknown
                )
            end

            if filtered_line == nil then
                keep = false
            elseif filtered_line ~= line then
                line = filtered_line
                filtered = true
            end
        end

        if keep then
            table.insert(outlines, line)
        else
            filtered = true
        end
    end

    f_in:close()

    -- If nothing was filtered out, don't write a new filter file.

    if not filtered then
        return nil
    end

    -- Write a new temporary session file with the requested commands filtered
    -- out, and return the path of it.

    local output = input .. ".tmpfiltered"
    local f_out = io.open(output, "w")
    if not f_out then
        return nil
    end

    for i, line in ipairs(outlines) do
        f_out:write(line .. "\n")
    end

    f_out:close()

    return output
end

-- Try to source the session with the given absolute path.
--
-- Returns true and the last error message (or nil if there was no error) if
-- the session was sourced, or false and an error message if it could not be
-- sourced at all.
function M._try_source(path)
    if M.options.debug and M.options.debug.unconditional_source then
        vim.cmd.source({ args = { path } })
        return true, nil
    end

    -- Sourcing a file from Lua runs it inside an active try conditional, and
    -- Vim aborts a sourced script at the first error when a try conditional is
    -- active. Prefixing the source command with `silent!` avoids that: Vim
    -- skips the failing command, records the error in v:errmsg, and continues
    -- with the rest of the session, which is exactly what we want. This keeps
    -- script-local variables working because the whole session is still one
    -- sourced script.
    vim.v.errmsg = ""
    local ok, err = pcall(function()
        vim.cmd("silent! source " .. vim.fn.fnameescape(path))
    end)

    if not ok then
        return false, tostring(err)
    end

    local errmsg = vim.v.errmsg
    return true, (errmsg ~= "" and errmsg or nil)
end

-- Wipe all buffers from the current session so they don't linger alongside the
-- session that is about to be loaded. This also closes windows and tabs that
-- display those buffers.
--
-- If any buffer has unsaved changes, prompt the user to save them first.
--
-- Returns true if the current session was wiped, or false if the user canceled
-- or the changes could not be saved.
function M._clear_session()
    local modified = false
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
            modified = true
            break
        end
    end

    if modified then
        local choice = vim.fn.confirm(
            "save unsaved changes before loading session?",
            "&Save\n&Discard\n&Cancel",
            3
        )
        if choice == 1 then
            local ok, err = pcall(vim.cmd.wall)
            if not ok then
                print("error saving current session: " .. tostring(err) .. "\n")
                return false
            end
        elseif choice ~= 2 then
            -- Cancel (3) or dismissed (0).
            return false
        end
    end

    local ok, err = pcall(vim.cmd, "silent! %bwipeout!")
    if not ok then
        print("error clearing current session: " .. tostring(err) .. "\n")
        return false
    end

    return true
end

-- Load the given session, or select a new session to load.
function M.load_session(params)
    local name
    if params.args and params.args ~= "" then
        name = params.args
    else
        local contents = M._list_sessions()
        if not contents or #contents == 0 then
            print("no sessions have been created; nothing to load\n")
        else
            vim.ui.select(
                contents,
                M._selection_options("Session to load:"),
                function(choice)
                    if choice and choice ~= "" then
                        M.load_session({ args = choice })
                    end
                end
            )
        end
        return
    end

    if name and name ~= "" then
        name = vim.fs.basename(name)
        local path = M._joinpath(M.options.storage_path, name)

        if not vim.uv.fs_stat(path) then
            print("session does not exist: " .. name .. "\n")
        elseif params.bang or M.current_session ~= name then
            if M.options.wipe_before_load then
                if not M._clear_session() then
                    print("session load aborted\n")
                    return
                end
                -- The previously loaded session is gone now, even if sourcing
                -- the new session fails below.
                M.current_session = nil
            end

            local filtered_path = M._filter_session(path)
            local source_path = filtered_path or path
            local source_success, source_errmsg = M._try_source(source_path)
            if filtered_path then
                os.remove(filtered_path)
            end

            if source_success then
                print("loaded session: " .. path .. "\n")
                if source_errmsg then
                    print(
                        "warning: some session commands failed (last error: "
                            .. source_errmsg
                            .. ")\n"
                    )
                end
                M.current_session = name
            else
                print("error loading session: " .. path .. "\n")
            end
        else
            print("session is already loaded\n")
        end
    else
        print("no session to load\n")
    end
end

-- Delete the given session, or select a session to delete.
function M.delete_session(params)
    local name
    if params.args and params.args ~= "" then
        name = params.args
    else
        local contents = M._list_sessions()
        if not contents or #contents == 0 then
            print("no sessions have been created; nothing to delete")
        else
            print("contents: " .. table.concat(contents, ", "))
            vim.ui.select(
                contents,
                M._selection_options("Session to delete:"),
                function(choice)
                    if choice and choice ~= "" then
                        M.delete_session({ args = choice })
                    end
                end
            )
        end
        return
    end

    if name and name ~= "" then
        name = vim.fs.basename(name)
        local path = M._joinpath(M.options.storage_path, name)

        if vim.uv.fs_stat(path) then
            local confirm = 1
            if not params.bang then
                confirm = vim.fn.confirm(
                    "delete session (" .. name .. ")?",
                    "&Yes\n&No",
                    2
                )
            end
            if confirm == 1 then
                os.remove(path)
                if M.current_session == name then
                    M.current_session = nil
                end
                print("deleted session: " .. path .. "\n")
            else
                print("session deletion aborted\n")
            end
        else
            print("session does not exist: " .. name .. "\n")
        end
    else
        print("no session to delete\n")
    end
end

return M
