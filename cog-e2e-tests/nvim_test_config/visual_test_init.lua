-- Visual test init script
-- Renders comprehensive mock data directly without a backend
-- Used for evaluating the look and feel of the chat UI

-- Paths (hardcoded for reliability in testing)
local project_root = "/Volumes/External/code-external/cog"
local cog_nvim_path = project_root .. "/cog.nvim"
local fixtures_path = project_root .. "/cog-e2e-tests/fixtures"

-- Add cog.nvim to runtime path
vim.opt.runtimepath:prepend(cog_nvim_path)

-- Disable features that interfere with testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.updatetime = 300
vim.opt.timeoutlen = 3000
vim.opt.ttimeoutlen = 10

-- Set leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Setup cog.nvim with visual testing settings
require("cog").setup({
  backend = {
    auto_start = false, -- No real backend needed
  },
  ui = {
    chat = {
      layout = "vsplit",
      position = "right",
      width = "50%", -- Wider for visual testing
      border = "rounded",
      input_height = 5,
      show_borders = true,
      show_header = true,
      message_padding = 1,
      user_icon = "●",
      assistant_icon = "◆",
      pending_message = "Thinking...",
      disable_input_while_waiting = false, -- Don't lock input for testing
    },
    tool_calls = {
      style = "card",
      icons = true,
      max_preview_lines = 8,
    },
  },
  file_operations = {
    auto_apply = true,
    auto_save = true,
    animate = false,
  },
  permissions = {
    defaults = {},
  },
})

-- Load and render test data after setup
vim.defer_fn(function()
  local chat = require("cog.ui.chat")
  local test_data = dofile(fixtures_path .. "/visual_test_data.lua")

  -- Open the chat UI
  chat.open()

  -- Small delay to ensure UI is ready
  vim.defer_fn(function()
    -- Render each item from test data
    for _, item in ipairs(test_data.items) do
      if item.type == "user_message" then
        chat.append("user", item.text)
      elseif item.type == "assistant_message" then
        chat.append("assistant", item.text)
      elseif item.type == "system_message" then
        chat.append("system", item.text)
      elseif item.type == "tool_call" then
        chat.upsert_tool_call(item.id, {
          kind = item.kind,
          title = item.title,
          status = item.status,
          command = item.command,
          output = item.output,
          diff = item.diff,
          locations = item.locations,
          exit_code = item.exit_code,
        })
      elseif item.type == "thinking" then
        -- Render thinking blocks as assistant message with <thinking> tags
        chat.append("assistant", "<thinking>\n" .. item.text .. "\n</thinking>")
      elseif item.type == "pending" then
        chat.begin_pending()
      end
    end

    -- Scroll to top after all content is loaded
    vim.defer_fn(function()
      local winid = vim.fn.win_getid()
      -- Find the chat window and scroll to top
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.api.nvim_buf_get_option(buf, "filetype")
        if ft == "markdown" then
          vim.api.nvim_win_set_cursor(win, { 1, 0 })
          break
        end
      end
      vim.notify("Visual test data loaded - " .. #test_data.items .. " items", vim.log.levels.INFO)
    end, 100)
  end, 200)
end, 500)
