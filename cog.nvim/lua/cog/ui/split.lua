local M = {}

local config = require("cog.config")
local icons = require("cog.ui.icons")

local state = {
  chat_win = nil,
  chat_buf = nil,
  input_win = nil,
  input_buf = nil,
  saved_win = nil,
  layout_type = nil,
  session_info = {
    title = "New Chat",
    tokens = 0,
    model = "",
  },
  -- Spinner animation state
  spinner = {
    timer = nil,
    frame = 1,
    active = false,
    message = "",
  },
}

-- Separator line between chat and input
local SEPARATOR = "─"

local function setup_chat_buffer(buf)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  -- Clean up any stale buffer with this name first
  local old_buf = vim.fn.bufnr("CogChat")
  if old_buf ~= -1 and old_buf ~= buf then
    pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
  end
  vim.api.nvim_buf_set_name(buf, "CogChat")
end

local function setup_input_buffer(buf)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  -- Clean up any stale buffer with this name first
  local old_buf = vim.fn.bufnr("CogInput")
  if old_buf ~= -1 and old_buf ~= buf then
    pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
  end
  vim.api.nvim_buf_set_name(buf, "CogInput")
end

-- Apply clean window options for a polished look
local function setup_window_options(win, is_input)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "signcolumn", "no")
  vim.api.nvim_win_set_option(win, "foldcolumn", "0")
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)
  vim.api.nvim_win_set_option(win, "cursorline", is_input or false)
  vim.api.nvim_win_set_option(win, "spell", false)
  vim.api.nvim_win_set_option(win, "list", false)

  -- Disable fold column completely
  pcall(vim.api.nvim_win_set_option, win, "foldmethod", "manual")
  pcall(vim.api.nvim_win_set_option, win, "foldenable", false)
end

-- Build winbar content for header
local function build_winbar()
  local cfg = config.get().ui.chat or {}
  if cfg.show_header == false then
    return ""
  end

  local parts = {}

  -- Title
  table.insert(parts, "%#CogHeaderTitle# # " .. state.session_info.title .. " %*")

  -- Right-aligned info
  table.insert(parts, "%=")

  -- Token count (if available)
  if state.session_info.tokens > 0 then
    local tokens_str = state.session_info.tokens
    if tokens_str >= 1000 then
      tokens_str = string.format("%.1fk", tokens_str / 1000)
    end
    table.insert(parts, "%#CogFooter#" .. tokens_str .. " tokens%*")
  end

  -- Model (if available)
  if state.session_info.model and state.session_info.model ~= "" then
    table.insert(parts, "%#CogFooter# │ " .. state.session_info.model .. " %*")
  end

  return table.concat(parts, "")
end

-- Update winbar content
function M.update_header()
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    local winbar = build_winbar()
    pcall(vim.api.nvim_win_set_option, state.chat_win, "winbar", winbar)
  end
end

-- Update session info
function M.set_session_info(info)
  if info.title then
    state.session_info.title = info.title
  end
  if info.tokens then
    state.session_info.tokens = info.tokens
  end
  if info.model then
    state.session_info.model = info.model
  end
  M.update_header()
end

-- Add input placeholder text
local function setup_input_placeholder(buf)
  local cfg = config.get().ui.chat or {}
  if cfg.show_input_placeholder == false then
    return
  end

  local ns = vim.api.nvim_create_namespace("cog_input_placeholder")

  local function update_placeholder()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local is_empty = #lines == 0 or (#lines == 1 and lines[1] == "")

    if is_empty then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, 0, 0, {
        virt_text = { { "Type your message... (Enter to send)", "CogInputPlaceholder" } },
        virt_text_pos = "overlay",
      })
    end
  end

  -- Update on text changes
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      vim.schedule(update_placeholder)
    end,
  })

  -- Initial update
  update_placeholder()
end

-- Create a separator line buffer
local function create_separator_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  return buf
end

function M.open(layout_type, width, input_height)
  layout_type = layout_type or "vsplit"
  local cfg = config.get().ui.chat or {}

  -- Check if already open
  if M.is_open() then
    M.focus()
    return state.chat_buf, state.input_buf
  end

  -- Save current window to return focus later
  state.saved_win = vim.api.nvim_get_current_win()
  state.layout_type = layout_type

  -- Parse width (handle both "40%" and 0.4)
  local width_ratio = 0.4
  if type(width) == "string" and width:match("%%") then
    local num_str = width:gsub("%%", "")
    width_ratio = tonumber(num_str) / 100
  elseif type(width) == "number" then
    width_ratio = width
  end

  -- Calculate dimensions
  local win_width = math.floor(vim.o.columns * width_ratio)
  local input_h = input_height or 5

  if layout_type == "vsplit" then
    -- Vertical split (sidebar on right)
    vim.cmd("botright " .. win_width .. "vsplit")
    state.chat_win = vim.api.nvim_get_current_win()

    -- Create or reuse chat buffer
    if state.chat_buf and vim.api.nvim_buf_is_valid(state.chat_buf) then
      vim.api.nvim_win_set_buf(state.chat_win, state.chat_buf)
    else
      state.chat_buf = vim.api.nvim_create_buf(false, true)
      setup_chat_buffer(state.chat_buf)
      vim.api.nvim_win_set_buf(state.chat_win, state.chat_buf)
    end

    -- Configure chat window
    vim.api.nvim_win_set_option(state.chat_win, "winfixwidth", true)
    setup_window_options(state.chat_win, false)

    -- Set up winbar for header (Neovim 0.8+)
    if cfg.show_header ~= false then
      M.update_header()
    end

    -- Create horizontal split for input
    vim.cmd("split")
    state.input_win = vim.api.nvim_get_current_win()

    -- Create or reuse input buffer
    if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
      vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
    else
      state.input_buf = vim.api.nvim_create_buf(false, true)
      setup_input_buffer(state.input_buf)
      vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
      setup_input_placeholder(state.input_buf)
    end

    -- Configure input window
    vim.api.nvim_win_set_option(state.input_win, "winfixheight", true)
    vim.api.nvim_win_set_height(state.input_win, input_h)
    setup_window_options(state.input_win, true)

    -- Set input window status line for visual separation
    if cfg.show_footer ~= false then
      local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
      if #cwd > 30 then
        cwd = "..." .. cwd:sub(-27)
      end
      local statusline = "%#CogFooter# " .. cwd .. " %=%#CogStatusOk#●%* Ready "
      pcall(vim.api.nvim_win_set_option, state.input_win, "statusline", statusline)
    end

    -- Resize chat window to take remaining space
    vim.api.nvim_set_current_win(state.chat_win)
    vim.cmd("resize " .. (vim.o.lines - input_h - 3))

  elseif layout_type == "hsplit" then
    -- Horizontal split (bottom panel)
    local height_ratio = 0.3
    if type(width) == "string" and width:match("%%") then
      local num_str = width:gsub("%%", "")
      height_ratio = tonumber(num_str) / 100
    elseif type(width) == "number" then
      height_ratio = width
    end
    local panel_height = math.floor(vim.o.lines * height_ratio)
    vim.cmd("botright " .. panel_height .. "split")

    -- Create vertical split inside the panel
    vim.cmd("vsplit")
    state.chat_win = vim.api.nvim_get_current_win()

    -- Create or reuse chat buffer
    if state.chat_buf and vim.api.nvim_buf_is_valid(state.chat_buf) then
      vim.api.nvim_win_set_buf(state.chat_win, state.chat_buf)
    else
      state.chat_buf = vim.api.nvim_create_buf(false, true)
      setup_chat_buffer(state.chat_buf)
      vim.api.nvim_win_set_buf(state.chat_win, state.chat_buf)
    end

    -- Configure chat window
    vim.api.nvim_win_set_option(state.chat_win, "winfixheight", true)
    setup_window_options(state.chat_win, false)

    -- Set up winbar for header
    if cfg.show_header ~= false then
      M.update_header()
    end

    -- Go to left window for input
    vim.cmd("wincmd h")
    state.input_win = vim.api.nvim_get_current_win()

    -- Create or reuse input buffer
    if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
      vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
    else
      state.input_buf = vim.api.nvim_create_buf(false, true)
      setup_input_buffer(state.input_buf)
      vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
      setup_input_placeholder(state.input_buf)
    end

    -- Configure input window
    vim.api.nvim_win_set_option(state.input_win, "winfixheight", true)
    setup_window_options(state.input_win, true)
  end

  -- Focus input window
  vim.api.nvim_set_current_win(state.input_win)

  return state.chat_buf, state.input_buf
end

function M.is_open()
  return state.chat_win and vim.api.nvim_win_is_valid(state.chat_win)
    and state.input_win and vim.api.nvim_win_is_valid(state.input_win)
end

function M.focus()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.input_win)
  end
end

function M.focus_chat()
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_set_current_win(state.chat_win)
  end
end

function M.focus_input()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_set_current_win(state.input_win)
  end
end

function M.get_chat_buf()
  return state.chat_buf
end

function M.get_input_buf()
  return state.input_buf
end

function M.get_chat_win()
  return state.chat_win
end

function M.get_input_win()
  return state.input_win
end

function M.scroll_to_bottom()
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) and state.chat_buf then
    local line_count = vim.api.nvim_buf_line_count(state.chat_buf)
    vim.api.nvim_win_set_cursor(state.chat_win, { line_count, 0 })
  end
end

function M.restore_focus()
  if state.saved_win and vim.api.nvim_win_is_valid(state.saved_win) then
    vim.api.nvim_set_current_win(state.saved_win)
  end
end

-- Stop spinner animation
local function stop_spinner()
  if state.spinner.timer then
    state.spinner.timer:stop()
    state.spinner.timer:close()
    state.spinner.timer = nil
  end
  state.spinner.active = false
  state.spinner.frame = 1
end

-- Update the status line with current spinner frame
local function update_statusline_with_spinner()
  if not state.input_win or not vim.api.nvim_win_is_valid(state.input_win) then
    stop_spinner()
    return
  end

  local cfg = config.get().ui.chat or {}
  if cfg.show_footer == false then
    return
  end

  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
  if #cwd > 30 then
    cwd = "..." .. cwd:sub(-27)
  end

  local status_icon = icons.spinner_frames[state.spinner.frame] or "◐"
  local statusline = "%#CogFooter# " .. cwd .. " %=%#CogStatusPending#" .. status_icon .. "%* " .. state.spinner.message .. " "
  pcall(vim.api.nvim_win_set_option, state.input_win, "statusline", statusline)
end

-- Start spinner animation
local function start_spinner(message)
  stop_spinner() -- Clean up any existing timer

  state.spinner.active = true
  state.spinner.message = message or "Thinking..."
  state.spinner.frame = 1

  -- Initial update
  update_statusline_with_spinner()

  -- Start animation timer (100ms interval)
  local timer = vim.loop.new_timer()
  state.spinner.timer = timer
  timer:start(100, 100, vim.schedule_wrap(function()
    if not state.spinner.active then
      stop_spinner()
      return
    end
    state.spinner.frame = (state.spinner.frame % #icons.spinner_frames) + 1
    update_statusline_with_spinner()
  end))
end

-- Update spinner message without restarting animation
local function update_spinner_message(message)
  if state.spinner.active then
    state.spinner.message = message or state.spinner.message
    update_statusline_with_spinner()
  end
end

-- Update status indicator (called during operations)
-- opts = { tool_name = "Read", tool_kind = "read" } for enhanced status
function M.set_status(status, message, opts)
  opts = opts or {}

  if not state.input_win or not vim.api.nvim_win_is_valid(state.input_win) then
    stop_spinner()
    return
  end

  local cfg = config.get().ui.chat or {}
  if cfg.show_footer == false then
    stop_spinner()
    return
  end

  -- Build context-aware status message
  local status_message = message
  if status == "pending" or status == "tool_running" then
    if opts.tool_name then
      status_message = "Calling " .. opts.tool_name .. "..."
    elseif opts.command then
      -- Truncate long commands
      local cmd = opts.command
      if #cmd > 30 then
        cmd = cmd:sub(1, 27) .. "..."
      end
      status_message = "Running: " .. cmd
    else
      status_message = message or "Thinking..."
    end
  end

  -- Handle animated pending/tool_running state
  if status == "pending" or status == "tool_running" then
    if state.spinner.active then
      -- Update message without restarting animation
      update_spinner_message(status_message)
    else
      start_spinner(status_message)
    end
    return
  end

  -- Stop animation for non-pending states
  stop_spinner()

  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
  if #cwd > 30 then
    cwd = "..." .. cwd:sub(-27)
  end

  local status_hl = "CogStatusOk"
  local status_icon = "●"
  local status_text = status_message or "Ready"

  if status == "error" then
    status_hl = "CogStatusError"
    status_icon = "●"
    status_text = status_message or "Error"
  end

  local statusline = "%#CogFooter# " .. cwd .. " %=%#" .. status_hl .. "#" .. status_icon .. "%* " .. status_text .. " "
  pcall(vim.api.nvim_win_set_option, state.input_win, "statusline", statusline)
end

-- Clean up spinner on close
function M.close()
  stop_spinner()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, false)
  end
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_win_close(state.chat_win, false)
  end
  state.chat_win = nil
  state.input_win = nil
end

return M
