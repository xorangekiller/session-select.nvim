-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

local M = {
    -- default configuration options for this plugin
    defaults = {
        -- directory where sessions are stored
        storage_path = vim.fs.normalize(vim.fn.stdpath("data") .. "/sessions"),
        -- automatically register the commands for this plugin?
        register_commands = true,
        -- options to allow filtering things out of existing sessions that are
        -- loaded (set to {} to disable filtering entirely)
        filter = {
            -- filter key mapping commands out of the session before loading it
            -- (which is particularly helpful if you have existing sessions
            -- that contain keybindings from plugins that you have since
            -- removed from your config)
            nomap = false,
        },
        -- options that should only be set by developers who are working on and
        -- debugging this module
        debug = {
            -- use our own internal implementation of the joinpath() function,
            -- even if we have a new enough version of Neovim that we don't
            -- need it (intended primarily for unit testing)
            joinpath_compat = false,
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
    M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

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
    })
    vim.api.nvim_create_user_command("LoadSession", M.load_session, {
        nargs = "?",
        bang = true, -- Always load the given session even if it is already loaded.
    })
    vim.api.nvim_create_user_command("DeleteSession", M.delete_session, {
        nargs = "?",
        bang = true, -- Delete the given session without asking.
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

-- Read the given session file, and filter out anything that we're configured
-- to remove.
--
-- Note: This is a helper function, not a command. Users of this plugin are not
-- expected to call it directly.
--
-- Returns: If anything was filtered out of the session file, the path of the
-- new filtered session file is returned. The caller is responsible for
-- removing it once it has been loaded. If nothing needed to be removed from
-- the session file, then nil is returned.
function M._filter_session(input)
    -- Shortcut: Don't bother reading the input file at all if no filter
    -- options are enabled.

    if not M.options or not M.options.filter then
        return nil
    end

    local have_enabled_filters = false
    for filter_option, filter_enabled in pairs(M.options.filter) do
        if filter_option and filter_enabled then
            have_enabled_filters = true
            break
        end
    end

    if not have_enabled_filters then
        return nil
    end

    -- Read the session file and filter out anything that we were asked to.

    local f_in = io.open(input, "r")
    if not f_in then
        f_out:close()
        return nil
    end

    local outlines = {}
    local filtered = false
    for line in f_in:lines() do
        if M.options.filter.nomap and line:find("^%a+map") then
            filtered = true
        else
            table.insert(outlines, line)
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

-- Try to source the session with the given absolute path, and return true if
-- successful, or false if not.
function M._try_source(path)
    vim.cmd.source({ args = { path } })
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
                { prompt = "Session to load:" },
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
            local filtered_path = M._filter_session(path)
            local source_success = false
            if filtered_path then
                source_success = M._try_source(filtered_path)
                os.remove(filtered_path)
            else
                source_success = M._try_source(path)
            end
            if source_success then
                print("loaded session: " .. path .. "\n")
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
                { prompt = "Session to delete:" },
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
