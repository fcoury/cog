local M = {}

local menu_ok, Menu = pcall(require, "nui.menu")
local config = require("cog.config")
local buttons = require("cog.ui.buttons")
local split = require("cog.ui.split")

local function select_option_id(options, desired_kind)
  if not options then
    return nil
  end

  for _, opt in ipairs(options) do
    if opt.kind == desired_kind or opt.label == desired_kind then
      return opt.optionId
    end
  end

  return nil
end

-- Render permission request inline in chat buffer
local function render_inline_permission(params, options, callback)
  local chat_buf = split.get_chat_buf()
  local chat_win = split.get_chat_win()

  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then
    return false
  end

  -- Build inline message
  local title = params.title or "Permission required"
  local message = params.message or ""

  -- Append permission request to chat
  local chat = require("cog.ui.chat")
  local meta = chat.append("system", title .. (message ~= "" and ("\n" .. message) or ""))

  -- Get the line where we appended
  local line = meta.content_start + meta.content_count - 1

  -- Convert options to button format
  local button_options = {}
  for _, opt in ipairs(options) do
    table.insert(button_options, {
      id = opt.optionId,
      label = opt.label or opt.kind or opt.optionId,
    })
  end

  -- Create button group at the end of the permission message
  buttons.create(chat_buf, line, button_options, function(selected_id)
    callback(selected_id)
  end)

  -- Focus the chat window so user can interact with buttons
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    vim.api.nvim_set_current_win(chat_win)
    -- Move cursor to the button line
    pcall(vim.api.nvim_win_set_cursor, chat_win, { line + 1, 0 })
  end

  return true
end

function M.request(params, callback)
  local options = params.options or {}
  local items = {}
  local done = false
  local timeout_handle = nil

  for _, opt in ipairs(options) do
    table.insert(items, {
      label = opt.label or opt.kind or opt.optionId,
      option_id = opt.optionId,
    })
  end

  if #items == 0 then
    callback(nil)
    return
  end

  local function finish(choice)
    if done then
      return
    end
    done = true
    if timeout_handle then
      timeout_handle:stop()
      timeout_handle:close()
      timeout_handle = nil
    end
    callback(choice)
  end

  local cfg = config.get()
  local timeout_ms = cfg.permissions and cfg.permissions.timeout_ms or 0
  local timeout_response = cfg.permissions and cfg.permissions.timeout_response or "reject_once"

  if timeout_ms > 0 then
    timeout_handle = vim.loop.new_timer()
    timeout_handle:start(timeout_ms, 0, function()
      local option_id = select_option_id(options, timeout_response)
      vim.schedule(function()
        -- Clear inline buttons if active
        buttons.clear()
        finish(option_id)
      end)
    end)
  end

  -- Try inline rendering first if chat is open
  if split.is_open() then
    local rendered = render_inline_permission(params, options, function(selected_id)
      finish(selected_id)
    end)
    if rendered then
      return
    end
  end

  -- Fallback to nui.menu or vim.ui.select
  if menu_ok then
    local menu_items = {}
    for _, item in ipairs(items) do
      table.insert(menu_items, Menu.item(item.label, { option_id = item.option_id }))
    end

    local menu = Menu({
      position = "50%",
      size = { width = 50, height = math.min(#menu_items + 2, 10) },
      border = { style = "rounded", text = { top = " Permission " } },
    }, {
      lines = menu_items,
      keymap = {
        focus_next = { "j", "<Down>" },
        focus_prev = { "k", "<Up>" },
        submit = { "<CR>" },
      },
      on_submit = function(item)
        finish(item.option_id)
        menu:unmount()
      end,
    })

    menu:mount()
    return
  end

  vim.ui.select(items, {
    prompt = params.title or "Permission required",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      finish(choice.option_id)
    else
      finish(nil)
    end
  end)
end

return M
