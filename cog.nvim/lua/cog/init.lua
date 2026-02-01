local M = {}

local config = require("cog.config")
local session = require("cog.session")
local ui = require("cog.ui")

function M.setup(opts)
  config.setup(opts)
  local cfg = config.get()

  require("cog.ui.highlights").setup()

  if cfg.keymaps then
    local km = cfg.keymaps
    if km.toggle_chat then
      vim.keymap.set("n", km.toggle_chat, function()
        M.toggle_chat()
      end, { desc = "Cog: Toggle chat" })
    end
    if km.open_chat then
      vim.keymap.set("n", km.open_chat, function()
        M.open_chat()
      end, { desc = "Cog: Open chat" })
    end
    if km.prompt then
      vim.keymap.set("n", km.prompt, function()
        M.prompt()
      end, { desc = "Cog: Prompt" })
    end
    if km.cancel then
      vim.keymap.set("n", km.cancel, function()
        session.cancel()
      end, { desc = "Cog: Cancel" })
    end
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      session.disconnect()
    end,
  })

  if cfg.backend and cfg.backend.auto_start then
    -- Defer connection to avoid blocking startup
    vim.defer_fn(function()
      local ok, err = pcall(session.connect)
      if not ok then
        vim.notify("cog.nvim: Failed to auto-connect: " .. tostring(err), vim.log.levels.ERROR)
      end
    end, 100)
  end
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

function M.close_chat()
  ui.chat.close()
end

function M.toggle_chat()
  ui.chat.toggle()
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
