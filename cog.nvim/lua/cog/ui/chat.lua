local M = {}

local config = require("cog.config")

local nui_ok, Popup = pcall(require, "nui.popup")
local layout_ok, Layout = pcall(require, "nui.layout")

local state = {
  bufnr = nil,
  winid = nil,
  last_role = nil,
  last_line = nil,
  layout = nil,
  messages = nil,
  input = nil,
  pending = {
    active = false,
    range = nil,
    timer = nil,
  },
}

local function ensure_buffer()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    return state.bufnr
  end

  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(state.bufnr, "bufhidden", "hide")
  return state.bufnr
end

local function get_message_buf()
  if state.messages and vim.api.nvim_buf_is_valid(state.messages.bufnr) then
    return state.messages.bufnr
  end
  return ensure_buffer()
end

local function send_input()
  if not state.input or not vim.api.nvim_buf_is_valid(state.input.bufnr) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.input.bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  vim.api.nvim_buf_set_lines(state.input.bufnr, 0, -1, false, {})

  if text and text ~= "" then
    require("cog.session").prompt(text)
  end
end

local function setup_input_keymaps(popup)
  if not popup or not popup.bufnr then
    return
  end

  local cfg = config.get().ui.chat or {}
  local submit = cfg.input_submit or "<C-CR>"
  local send_on_enter = cfg.input_send_on_enter ~= false

  if send_on_enter then
    popup:map("i", "<CR>", send_input, { noremap = true, silent = true })
  end

  popup:map("i", submit, send_input, { noremap = true, silent = true })
  popup:map("n", "<CR>", send_input, { noremap = true, silent = true })
  if submit ~= "<CR>" then
    popup:map("n", submit, send_input, { noremap = true, silent = true })
  end
end

local function set_input_locked(locked)
  if not state.input or not state.input.bufnr or not vim.api.nvim_buf_is_valid(state.input.bufnr) then
    return
  end
  local value = not locked
  if vim.api.nvim_set_option_value then
    vim.api.nvim_set_option_value("modifiable", value, { buf = state.input.bufnr })
  else
    vim.api.nvim_buf_set_option(state.input.bufnr, "modifiable", value)
  end
end

local function should_auto_open()
  local cfg = config.get().ui.chat or {}
  return cfg.auto_open == true
end

local function popup_buf_valid(popup)
  return popup and popup.bufnr and vim.api.nvim_buf_is_valid(popup.bufnr)
end

function M.open()
  if nui_ok and layout_ok then
    if state.layout then
      if popup_buf_valid(state.messages) and popup_buf_valid(state.input) then
        state.layout:mount()
        return
      end
      pcall(function()
        state.layout:unmount()
      end)
      state.layout = nil
      state.messages = nil
      state.input = nil
    end

    local cfg = config.get().ui.chat

    local message_bufnr = ensure_buffer()
    state.messages = Popup({
      border = { style = cfg.border or "rounded" },
      focusable = false,
      bufnr = message_bufnr,
      buf_options = { filetype = "markdown" },
    })

    state.input = Popup({
      border = { style = cfg.border or "rounded", text = { top = " Input " } },
      enter = true,
      focusable = true,
      buf_options = { filetype = "markdown" },
    })

    local input_height = cfg.input_height or 20
    local position = cfg.position or "right"
    if position == "right" then
      position = { row = 0, col = "100%" }
    elseif position == "left" then
      position = { row = 0, col = 0 }
    elseif position == "center" then
      position = { row = "50%", col = "50%" }
    end

    local layout = Layout(
      {
        relative = "editor",
        position = position,
        size = {
          width = cfg.width or "40%",
          height = "100%",
        },
      },
      Layout.Box({
        Layout.Box(state.messages, { size = "80%" }),
        Layout.Box(state.input, { size = input_height .. "%" }),
      }, { dir = "col" })
    )

    state.layout = layout
    layout:mount()

    setup_input_keymaps(state.input)
    if vim.fn.exists(":RenderMarkdown") == 2 then
      vim.api.nvim_buf_call(state.messages.bufnr, function()
        vim.cmd("RenderMarkdown")
      end)
    end
    return
  end

  local bufnr = ensure_buffer()

  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    return
  end

  vim.cmd("vsplit")
  state.winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.winid, bufnr)
  if vim.fn.exists(":RenderMarkdown") == 2 then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("RenderMarkdown")
    end)
  end
end

function M.append(role, text)
  local bufnr = get_message_buf()

  if should_auto_open() and state.messages == nil and (not state.winid or not vim.api.nvim_win_is_valid(state.winid)) then
    M.open()
  end

  local prefix = role == "user" and "User:" or role == "assistant" and "Assistant:" or "Cog:"
  local lines = {}
  for line in tostring(text):gmatch("[^\n]*\n?") do
    if line == "" then
      break
    end
    local cleaned = line:gsub("\n$", "")
    table.insert(lines, cleaned)
  end

  if #lines == 0 then
    lines = { tostring(text) }
  end

  local existing = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, existing, existing, false, { prefix })
  vim.api.nvim_buf_set_lines(bufnr, existing + 1, existing + 1, false, lines)

  state.last_role = role
  state.last_line = existing + 1 + #lines

  if state.messages and state.messages.winid then
    vim.api.nvim_win_set_cursor(state.messages.winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
  elseif state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_set_cursor(state.winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
  end

  return {
    prefix_line = existing + 1,
    content_start = existing + 2,
    content_count = #lines,
  }
end

function M.append_chunk(role, text)
  local bufnr = get_message_buf()

  if not state.last_line or state.last_role ~= role then
    M.append(role, text)
    return
  end

  local current = vim.api.nvim_buf_get_lines(bufnr, state.last_line - 1, state.last_line, false)[1]
  if current == nil then
    M.append(role, text)
    return
  end

  local parts = vim.split(tostring(text), "\n", { plain = true })
  local first = current .. (parts[1] or "")
  vim.api.nvim_buf_set_lines(bufnr, state.last_line - 1, state.last_line, false, { first })

  if #parts > 1 then
    local extra = {}
    for i = 2, #parts do
      table.insert(extra, parts[i])
    end
    vim.api.nvim_buf_set_lines(bufnr, state.last_line, state.last_line, false, extra)
    state.last_line = state.last_line + #extra
  end

  if state.messages and state.messages.winid then
    vim.api.nvim_win_set_cursor(state.messages.winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
  elseif state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_set_cursor(state.winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
  end
end

function M.begin_pending()
  local cfg = config.get().ui.chat or {}
  if state.pending.active then
    return
  end

  local meta = M.append("system", cfg.pending_message or "Thinking...")
  state.pending.active = true
  state.pending.range = {
    start = meta.prefix_line - 1,
    finish = (meta.content_start - 1) + meta.content_count,
  }

  if cfg.disable_input_while_waiting ~= false then
    set_input_locked(true)
  end

  if cfg.pending_timeout_ms and cfg.pending_timeout_ms > 0 then
    local timer = vim.loop.new_timer()
    state.pending.timer = timer
    timer:start(cfg.pending_timeout_ms, 0, vim.schedule_wrap(function()
      if state.pending.active then
        M.append("system", cfg.pending_timeout_message or "No response yet; still waiting...")
      end
    end))
  end
end

function M.clear_pending()
  if not state.pending.active then
    return
  end

  if state.pending.timer then
    state.pending.timer:stop()
    state.pending.timer:close()
    state.pending.timer = nil
  end

  local bufnr = get_message_buf()
  local range = state.pending.range
  if range and vim.api.nvim_buf_is_valid(bufnr) then
    local start = math.max(range.start, 0)
    local finish = math.max(range.finish or start, start)
    if finish > start then
      pcall(vim.api.nvim_buf_set_lines, bufnr, start, finish, false, {})
    end
  end

  state.pending.active = false
  state.pending.range = nil
  state.last_role = nil
  state.last_line = nil

  set_input_locked(false)
end

function M.is_pending()
  return state.pending.active
end

return M
