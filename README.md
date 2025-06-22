# session-select.nvim

Lightweight session management plugin for Neovim that allows users to easily
save, visually select and load, and delete sessions with minimal automation.

## Motivation

This plugin is a *very* simple wrapper over the built-in `:mksession` command
that provides a little extra tooling to make it easy to save sessions in a
predefined location and allow the user to visually select sessions to load from
that location.

Unlike most other Neovim session plugins, this one does *not* attempt to save
or load sessions automatically. It merely provides commands to make it more
convenient for the user to do so. It also does *not* attempt to save any
additional metadata along with the session. It works with pure session files
create with the built-in `:mksession` command, including those created manually
or created with other plugins.

The core idea of this plugin is that it should be as easy and convenient as
possible for users to save, load, and delete sessions themselves without
leaving Neovim or needing to look in other locations.

This plugin does *not* attempt to do anything that the user doesn't explicitly
tell it to. It aims to be simple, boring, and predictable. If you would like
automatic session saving/loading or explicit integration with other popular
Neovim plugins, you may want to use one of the other excellent session
management plugins for Neovim such as
[neovim-session-manager](https://github.com/Shatur/neovim-session-manager) or
[auto-session](https://github.com/rmagatti/auto-session) instead.

## Features

- Save sessions with `:mksession` in a preconfigured directory.
- Use [`vim.ui.select`](https://neovim.io/doc/user/lua.html#vim.ui.select())
  with any registered picker (such as
  [fzf-lua](https://github.com/ibhagwan/fzf-lua) or
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)) to allow
  the user to interactive select a session to load or delete.
- Prompt the user for a name for the session to save if one was not provided
  in the command.
- Automatically update the last session to be saved or loaded when saving
  rather than prompting the user for a session name if there was an existing
  session.
- Ask the user before overwriting or deleting a session (unless `!` was
  specified in the command name to tell it to save/delete without asking).

## Requirements

- Neovim >= 0.8.0

## Installation

Install using your package manager of choice. You may need to call
`require("session-select").setup({})` if your plugin manager to configure the
plugin and create the commands if your plugin manager does not do so for you.

For example, using [`lazy.nvim`](https://github.com/folke/lazy.nvim):
```lua
require("lazy").setup({
  {
    "xorangekiller/session-select.nvim",
    opts = {},
  }
})
```

Optionally if you would like to lazily load this plugin with `lazy.nvim`, you
can do so by specifying the commands to load. Like this:
```lua
require("lazy").setup({
  {
    "xorangekiller/session-select.nvim",
    lazy = true,
    cmd = {
      "SaveSession",
      "LoadSession",
      "DeleteSession",
    },
    opts = {},
  }
})
```

## Configuration

The default configuration options for this plugin are as follows. Any default
may be overridden by supplying it to the `setup()` function for this plugin.
```lua
{
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
}
```

## Usage

There are three command provided by this plugin.

- `:SaveSession` will save your current session.
  - It will ask before overwriting an existing session.
    - If `!` is supplied, it will *not* ask before overwriting an existing
      session, and will just overwrite it with no prompting.
  - The user may supply a session name after the command, and it will be used
    rather than prompting for a name of the session to save.
  - It will automatically save to the last session that was saved or loaded if
    no session name was supplied after the command.
    - If there is no "last session", the user will be prompted to enter a
      session name.
- `:LoadSession` will load a saved session.
  - Normally if you select the session that is already loaded, it will *not* be
    reloaded unless you supply `!` after the command name.
  - The user may supply a session name to load after the command, and it will
    be used rather than prompting the user to select an existing session.
- `:DeleteSession` will delete a saved session.
  - It will ask before deleting a session.
    - If `!` is supplied, it will *not* ask before deleting a session.
  - If the current session is deleted, it will not be unloaded. Only the file
    on disk will be deleted.
  - The user may supply a session name after the command, and that is the
    session that will be deleted.

## Developing

If you are working on adding new features or fixing bugs in this plugin, there
are two types of testing that you should do.
1. **Required:** Run the unit tests with `make test`. This tests in a clean
   environment without your normal Neovim config using
   [`plenary.nvim`](https://github.com/nvim-lua/plenary.nvim)'s unit testing
   framework. If you add any new functionality, please make sure that you also
   add a unit test for it!
2. **Recommended:** You may also want to test your changes manually by using
   the plugin in your Neovim instance with your plugins so that you can make
   sure that they *look* and *feel* right, and that you don't run into any
   issues that you may have missed in your unit tests. Technically this step is
   optional because the unit tests *should* cover the full functionality, but
   it is recommended that you do it nonetheless.

For example, loading the local in-development version of this plugin from a
local directory rather than from its canonical source on GitHub with
[`lazy.nvim`](https://github.com/folke/lazy.nvim) so that you can do your
manual "look and feel" trial/testing before committing it may look something
like this:
```lua
require("lazy").setup({
  {
    dir = vim.fs.joinpath(vim.uv.os_homedir(), "Projects/session-select.nvim"),
    name = "xorangekiller/session-select.nvim",
    opts = {},
  }
})
```
