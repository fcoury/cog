local M = {}

local config = require("cog.config")
local session = require("cog.session")
local ui = require("cog.ui")

function M.setup(opts)
  config.setup(opts)
end

function M.start()
  session.connect()
  ui.chat.open()
end

function M.stop()
  session.disconnect()
end

function M.open_chat()
  ui.chat.open()
end

function M.prompt()
  vim.ui.input({ prompt = "Cog: " }, function(input)
    if not input or input == "" then
      return
    end
    session.prompt(input)
  end)
end

return M
