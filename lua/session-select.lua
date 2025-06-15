-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Join the given paths into a single path.
--
-- This function emulates vim.fs.joinpath() on Neovim versions prior to 0.10.0.
-- It can be safely removed once we no longer care about supporting earlier
-- versions.
local function joinpath(...)
    if vim.fn.has("nvim-0.10.0") == 1 then
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

local M = {
    -- default configuration options for this plugin
    defaults = {
        -- directory where sessions are stored
        storage_path = joinpath(vim.fn.stdpath("data"), "sessions"),
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

-- Save the current session with the given name, and set it as our current
-- session so that the name may be omitted the next time we save.
function M.save_session(params)
    local name
    if params.args ~= "" then
        name = params.args
    elseif not (M.current_session == nil) then
        name = M.current_session
    else
        name = vim.fn.input("name: ")
        -- The Vim input() function doesn't print a newline after the user
        -- presses enter. That technically doesn't really affect anything, but
        -- it makes anything that we print after that run into it, which looks
        -- weird. Printing a newline preemptively makes it look better.
        print("\n")
    end

    if name ~= "" then
        name = vim.fs.basename(name)
        local path = joinpath(M.options.storage_path, name)

        -- Create the directory to save the sessions if it doesn't already
        -- exist.
        if not vim.uv.fs_stat(M.options.storage_path) then
            uv.fs_mkdir(M.options.storage_path)
        end

        if next(vim.fs.find(name, { path = M.options.storage_path })) == nil then
            vim.cmd.mksession({ args = { path } })
            M.current_session = name
            print("session saved: " .. path)
        else
            local confirm = 1
            if not params.bang then
                confirm = vim.fn.confirm("overwrite session?", "&Yes\n&No", 2)
            end
            if confirm == 1 then
                vim.cmd.mksession({
                    args = { path },
                    bang = true,
                })
                M.current_session = name
                print("session updated: " .. path)
            else
                print("session not updated")
            end
        end
    else
        print("no session written")
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
function M.filter_session(input)
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

-- Load the given session, or select a new session to load.
function M.load_session(params)
    local name
    if params.args ~= "" then
        name = params.args
    else
        local contents = {}
        for entry in vim.fs.dir(M.options.storage_path) do
            if entry:find(".tmpfiltered$") then
                os.remove(entry)
            else
                table.insert(contents, entry)
            end
        end
        vim.ui.select(
            contents,
            { prompt = "Session to load:" },
            function(choice)
                if choice ~= nil then
                    M.load_session({ args = choice })
                end
            end
        )
        return
    end

    if name ~= nil then
        name = vim.fs.basename(name)
        local path = joinpath(M.options.storage_path, name)

        if params.bang or M.current_session ~= name then
            local filtered_path = M.filter_session(path)
            if filtered_path then
                vim.cmd.source({ args = { filtered_path } })
                os.remove(filtered_path)
            else
                vim.cmd.source({ args = { path } })
            end
            M.current_session = name
            print("loaded session: " .. path)
        else
            print("session is already loaded")
        end
    else
        print("no session to load")
    end
end

-- Delete the given session, or select a session to delete.
function M.delete_session(params)
    local name
    if params.args ~= "" then
        name = params.args
    else
        local contents = {}
        if vim.uv.fs_stat(M.options.storage_path) then
            for entry in vim.fs.dir(M.options.storage_path) do
                table.insert(contents, entry)
            end
        end
        if not contents then
            print("no sessions have been created; nothing to delete")
        else
            vim.ui.select(
                contents,
                { prompt = "Session to delete:" },
                function(choice)
                    if choice ~= nil then
                        M.delete_session({ args = choice })
                    end
                end
            )
        end
        return
    end

    if name ~= nil then
        name = vim.fs.basename(name)
        local path = joinpath(M.options.storage_path, name)

        local confirm = 1
        if not params.bang then
            confirm = vim.fn.confirm("delete session?", "&Yes\n&No", 2)
        end
        if confirm == 1 then
            if vim.uv.fs_stat(path) then
                os.remove(path)
                if M.current_session == name then
                    M.current_session = nil
                end
                print("deleted session: " .. path)
            else
                print("session does not exist: " .. name)
            end
        else
            print("session deletion aborted")
        end
    else
        print("no session to delete")
    end
end

return M
