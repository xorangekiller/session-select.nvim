-- Copyright (c) 2025 Karl Lenz <xorangekiller@gmail.com>
-- SPDX-License-Identifier: MIT

-- Test command registration.
describe("register", function()
    local ss = require("session-select")

    -- Ensure that the commands are **not** registered when command
    -- registration is disabled in the configuration.
    it("command registration disabled", function()
        ss.setup({ register_commands = false })
        local commands = vim.api.nvim_get_commands({})
        assert.falsy(commands.SaveSession)
        assert.falsy(commands.LoadSession)
        assert.falsy(commands.DeleteSession)
    end)

    -- Ensure that the commands are registered in the default configuration.
    it("commands registered by default", function()
        ss.setup({})
        local commands = vim.api.nvim_get_commands({})
        assert.truthy(commands.SaveSession)
        assert.truthy(commands.LoadSession)
        assert.truthy(commands.DeleteSession)
    end)
end)
