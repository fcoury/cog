local M = {}

local config = require("cog.config")
local split = require("cog.ui.split")
local icons = require("cog.ui.icons")

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
  layout_type = nil,
  pending = {
    active = false,
    range = nil,
    timer = nil,
    -- Save message state before pending so we can restore it
    saved_last_role = nil,
    saved_last_line = nil,
  },
  -- Track message blocks for styling
  message_blocks = {},
  tool_calls = {},
  stream = {
    active = false,
    role = nil,
    anchor_line = nil,
    block_index = nil,
    idle_timer = nil,
    kind = nil,
  },
  -- Token tracking for messages
  current_message_tokens = 0,
}

-- Message border characters
local BORDER = {
  user = "┃",
  assistant = "│",
  system = "┊",
}

-- Track fold ranges for tool output
local fold_ranges = {}

-- Custom foldtext function for tool output folds
-- Returns a function that can be used as foldtext
_G.CogFoldText = function()
  local line_count = vim.v.foldend - vim.v.foldstart + 1
  -- Get the accent bar from the first folded line to preserve style
  local first_line = vim.fn.getline(vim.v.foldstart)
  local accent_prefix = first_line:match("^(│[┃╏]?)") or "│┃"
  return string.format("%s  ▸ %d more lines (za to toggle)", accent_prefix, line_count)
end

-- Setup fold settings for a window displaying the chat buffer
local function setup_fold_settings(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  vim.api.nvim_win_call(winid, function()
    vim.opt_local.foldmethod = "manual"
    vim.opt_local.foldenable = true
    vim.opt_local.foldlevel = 0 -- Start with all folds closed
    vim.opt_local.foldminlines = 1
    vim.opt_local.foldtext = "v:lua.CogFoldText()"
  end)
end

-- Create a fold for tool output and close it
local function create_tool_fold(bufnr, start_line, end_line, hidden_count)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Store fold range for later recreation if needed
  table.insert(fold_ranges, {
    bufnr = bufnr,
    start_line = start_line,
    end_line = end_line,
    hidden_count = hidden_count,
  })

  -- Find the window displaying this buffer
  local chat_win = split.get_chat_win()
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    -- Ensure fold settings are applied to the window
    setup_fold_settings(chat_win)

    -- Create fold in the context of the chat window
    vim.api.nvim_win_call(chat_win, function()
      -- Create fold from start_line to end_line (1-indexed for vim commands)
      local ok, err = pcall(vim.cmd, string.format("%d,%dfold", start_line + 1, end_line + 1))
      if ok then
        -- Close the fold so it starts collapsed
        pcall(vim.cmd, string.format("%dfoldclose", start_line + 1))
      end
    end)
  end
end

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
  if state.layout_type == "popup" then
    if state.messages and vim.api.nvim_buf_is_valid(state.messages.bufnr) then
      return state.messages.bufnr
    end
  else
    local buf = split.get_chat_buf()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      return buf
    end
  end
  return ensure_buffer()
end

-- Format message lines with border character
local function format_message_lines(role, lines)
  local cfg = config.get().ui.chat or {}
  local show_borders = cfg.show_borders ~= false

  if not show_borders then
    return lines
  end

  local border = BORDER[role] or BORDER.system
  local formatted = {}
  for _, line in ipairs(lines) do
    table.insert(formatted, border .. " " .. line)
  end
  return formatted
end

-- Get role header with icon
local function get_role_header(role)
  local cfg = config.get().ui.chat or {}
  local role_icons = {
    user = cfg.user_icon or "●",
    assistant = cfg.assistant_icon or "◆",
    system = "○",
  }
  local names = {
    user = "You",
    assistant = "Assistant",
    system = "System",
  }
  local icon = role_icons[role] or role_icons.system
  local name = names[role] or "Cog"
  return icon .. " " .. name
end

-- Get the width of the chat window
local function get_chat_width()
  if state.layout_type == "popup" then
    if state.messages and state.messages.winid and vim.api.nvim_win_is_valid(state.messages.winid) then
      return vim.api.nvim_win_get_width(state.messages.winid)
    end
  else
    local win = split.get_chat_win()
    if win and vim.api.nvim_win_is_valid(win) then
      return vim.api.nvim_win_get_width(win)
    end
  end
  return 80 -- fallback
end

-- Add separator line after header using virtual text
local function add_header_separator(bufnr, line, header_text, role)
  local ns = vim.api.nvim_create_namespace("cog_chat_styling")
  local width = get_chat_width()
  local header_width = vim.fn.strdisplaywidth(header_text)
  local separator_char = "─"
  local separator_len = math.max(0, width - header_width - 2) -- -2 for space before separator

  if separator_len > 0 then
    local separator = " " .. string.rep(separator_char, separator_len)
    local sep_hl = "CogSeparator"
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, #header_text, {
      virt_text = { { separator, sep_hl } },
      virt_text_pos = "overlay",
      priority = 15,
    })
  end
end

-- Apply extmarks for message styling
local function apply_message_styling(bufnr, role, start_line, end_line)
  local ns = vim.api.nvim_create_namespace("cog_chat_styling")
  local hl_groups = {
    user = "CogUserMessage",
    assistant = "CogAssistantMessage",
    system = "CogSystemMessage",
  }
  local border_groups = {
    user = "CogUserBorder",
    assistant = "CogAssistantBorder",
    system = "CogSystemBorder",
  }

  local hl = hl_groups[role] or hl_groups.system
  local border_hl = border_groups[role] or border_groups.system

  -- Apply line highlights and border coloring
  for line = start_line, end_line do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, 0, {
      end_row = line,
      end_col = 0,
      line_hl_group = hl,
      priority = 10,
    })
    -- Highlight just the border character (first 1-2 chars)
    local line_content = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
    if #line_content > 0 then
      local border_len = line_content:match("^[┃│┊] ") and 2 or 1
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, 0, {
        end_row = line,
        end_col = border_len,
        hl_group = border_hl,
        priority = 20,
      })
    end
  end
end

local function split_lines(text)
  local raw_lines = {}
  for line in tostring(text):gmatch("[^\n]*\n?") do
    if line == "" then
      break
    end
    local cleaned = line:gsub("\n$", "")
    table.insert(raw_lines, cleaned)
  end
  if #raw_lines == 0 then
    raw_lines = { tostring(text) }
  end
  return raw_lines
end

local function clear_stream_timer()
  if state.stream.idle_timer then
    state.stream.idle_timer:stop()
    state.stream.idle_timer:close()
    state.stream.idle_timer = nil
  end
end

local function normalize_stream_kind(kind)
  if kind == "thought" then
    return "thought"
  end
  return "message"
end

local function reset_stream_timer()
  local cfg = config.get().ui.chat or {}
  local timeout_ms = cfg.stream_idle_timeout_ms
  if not timeout_ms or timeout_ms <= 0 then
    clear_stream_timer()
    return
  end

  clear_stream_timer()
  local timer = vim.loop.new_timer()
  state.stream.idle_timer = timer
  timer:start(timeout_ms, 0, vim.schedule_wrap(function()
    if state.stream.active then
      M.end_stream()
    end
  end))
end

local function shift_message_blocks_after(index, delta)
  if not index or delta == 0 then
    return
  end
  for i = index + 1, #state.message_blocks do
    local block = state.message_blocks[i]
    block.header_line = block.header_line + delta
    block.content_start = block.content_start + delta
    block.content_end = block.content_end + delta
  end
end

local function replace_message_block(block_index, role, raw_lines)
  local bufnr = get_message_buf()
  local block = state.message_blocks[block_index]
  if not block then
    return
  end

  local formatted = format_message_lines(role, raw_lines)
  local old_end = block.content_end
  local old_count = block.content_end - block.content_start + 1
  local new_count = #formatted

  vim.api.nvim_buf_set_lines(
    bufnr,
    block.content_start,
    block.content_end + 1,
    false,
    formatted
  )

  local delta = new_count - old_count
  if delta ~= 0 then
    block.content_end = block.content_end + delta
    shift_message_blocks_after(block_index, delta)

    if state.last_line then
      local last_zero_based = state.last_line - 1
      if last_zero_based > old_end then
        state.last_line = state.last_line + delta
      elseif last_zero_based == old_end then
        state.last_line = block.content_end + 1
      end
    end

    if state.stream.active and state.stream.anchor_line then
      local anchor_zero_based = state.stream.anchor_line - 1
      if anchor_zero_based > old_end then
        state.stream.anchor_line = state.stream.anchor_line + delta
      end
    end
  end

  apply_message_styling(bufnr, role, block.content_start, block.content_end)
end

function M.send_input()
  local text = nil
  
  if state.layout_type == "popup" and state.input then
    -- Popup mode
    if not vim.api.nvim_buf_is_valid(state.input.bufnr) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(state.input.bufnr, 0, -1, false)
    text = table.concat(lines, "\n")
    vim.api.nvim_buf_set_lines(state.input.bufnr, 0, -1, false, {})
  else
    -- Split mode
    local input_buf = split.get_input_buf()
    if not input_buf or not vim.api.nvim_buf_is_valid(input_buf) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    text = table.concat(lines, "\n")
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, {})
  end

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
    popup:map("i", "<CR>", M.send_input, { noremap = true, silent = true })
  end

  popup:map("i", submit, M.send_input, { noremap = true, silent = true })
  popup:map("n", "<CR>", M.send_input, { noremap = true, silent = true })
  if submit ~= "<CR>" then
    popup:map("n", submit, M.send_input, { noremap = true, silent = true })
  end
end

local function set_input_locked(locked)
  local input_buf = nil
  
  if state.layout_type == "popup" and state.input then
    input_buf = state.input.bufnr
  else
    input_buf = split.get_input_buf()
  end
  
  if not input_buf or not vim.api.nvim_buf_is_valid(input_buf) then
    return
  end
  
  local value = not locked
  if vim.api.nvim_set_option_value then
    vim.api.nvim_set_option_value("modifiable", value, { buf = input_buf })
  else
    vim.api.nvim_buf_set_option(input_buf, "modifiable", value)
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
  local cfg = config.get().ui.chat
  local layout_type = cfg.layout or "popup"
  
  -- Store layout type for later use
  state.layout_type = layout_type
  
  if layout_type == "popup" and nui_ok and layout_ok then
    -- Use nui.nvim popup layout
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
  else
    -- Use native split layout
    local chat_buf, input_buf = split.open(layout_type, cfg.width, cfg.input_height)
    
    if chat_buf and input_buf then
      state.bufnr = chat_buf
      
      -- Setup input keymaps for split
      local input_win = split.get_input_win()
      if input_win then
        -- Map <CR> to send in input buffer
        vim.api.nvim_buf_set_keymap(input_buf, "i", "<CR>", 
          "<cmd>lua require('cog.ui.chat').send_input()<cr>",
          { noremap = true, silent = true })
        vim.api.nvim_buf_set_keymap(input_buf, "n", "<CR>", 
          "<cmd>lua require('cog.ui.chat').send_input()<cr>",
          { noremap = true, silent = true })
      end
      
      if vim.fn.exists(":RenderMarkdown") == 2 then
        vim.api.nvim_buf_call(chat_buf, function()
          vim.cmd("RenderMarkdown")
        end)
      end
    end
  end
end

-- Apply styled thinking header with separator (moved here for forward reference)
local function render_thinking_header(bufnr, line)
  local ns = vim.api.nvim_create_namespace("cog_thinking")
  local thinking_icon = icons.tool_icons.thinking or "󰠗"
  local width = get_chat_width()
  local header_text = thinking_icon .. " Thinking"
  local header_width = vim.fn.strdisplaywidth(header_text)
  local separator_len = math.max(0, width - header_width - 4) -- -4 for border + spaces

  local separator = " " .. string.rep("─", separator_len)

  -- Set extmark for the styled header
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, 0, {
    end_row = line,
    end_col = 0,
    line_hl_group = "CogThinkingHeader",
    priority = 15,
  })

  -- Get the actual line content to find where header text ends
  local line_content = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  local content_len = #line_content

  -- Add separator as virtual text at end of line
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, content_len, {
    virt_text = { { separator, "CogSeparator" } },
    virt_text_pos = "overlay",
    priority = 16,
  })
end

-- Process thinking tags in text, returns processed lines and thinking region info
local function process_thinking_tags(lines)
  local result = {}
  local thinking_regions = {} -- {start_line, end_line} pairs for styling
  local in_thinking = false
  local thinking_start = nil
  local thinking_icon = icons.tool_icons.thinking or "󰠗"

  for i, line in ipairs(lines) do
    -- Check for <thinking> tag (with or without closing >)
    if line:match("^%s*<thinking>?%s*$") then
      in_thinking = true
      thinking_start = #result + 1
      -- Replace with styled header
      table.insert(result, thinking_icon .. " Thinking")
    -- Check for </thinking> tag
    elseif line:match("^%s*</thinking>%s*$") then
      if in_thinking and thinking_start then
        table.insert(thinking_regions, {
          start_line = thinking_start,
          end_line = #result,
        })
      end
      in_thinking = false
      thinking_start = nil
      -- Add separator line and blank line after thinking block
      local width = get_chat_width()
      local separator_width = math.max(20, width - 4)
      local separator = string.rep("─ ", math.floor(separator_width / 2))
      table.insert(result, separator)
      table.insert(result, "")
    else
      table.insert(result, line)
    end
  end

  return result, thinking_regions
end

function M.append(role, text)
  local bufnr = get_message_buf()
  local cfg = config.get().ui.chat or {}

  if should_auto_open() and state.messages == nil and (not state.winid or not vim.api.nvim_win_is_valid(state.winid)) then
    M.open()
  end

  -- Parse text into lines
  local raw_lines = split_lines(text)

  -- Process thinking tags if present
  local processed_lines, thinking_regions = process_thinking_tags(raw_lines)
  raw_lines = processed_lines

  local existing = vim.api.nvim_buf_line_count(bufnr)
  local message_padding = cfg.message_padding or 1

  -- Add padding before message (except for first message)
  local padding_lines = {}
  if existing > 1 then
    for _ = 1, message_padding do
      table.insert(padding_lines, "")
    end
  end

  -- Create header line
  local header = get_role_header(role)

  -- Format content lines with border
  local formatted_lines = format_message_lines(role, raw_lines)

  -- Calculate positions
  local padding_start = existing
  local header_line = padding_start + #padding_lines
  local content_start = header_line + 1
  local content_end = content_start + #formatted_lines - 1

  -- Write to buffer
  if #padding_lines > 0 then
    vim.api.nvim_buf_set_lines(bufnr, padding_start, padding_start, false, padding_lines)
  end
  vim.api.nvim_buf_set_lines(bufnr, header_line, header_line, false, { header })
  vim.api.nvim_buf_set_lines(bufnr, content_start, content_start, false, formatted_lines)

  -- Apply styling
  local header_hl = role == "user" and "CogChatUserHeader"
    or role == "assistant" and "CogChatAssistantHeader"
    or "CogChatSystemHeader"
  local ns = vim.api.nvim_create_namespace("cog_chat_styling")
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, header_line, 0, {
    end_row = header_line,
    end_col = 0,
    line_hl_group = header_hl,
    priority = 10,
  })

  -- Add separator line after header
  add_header_separator(bufnr, header_line, header, role)

  -- Apply content styling
  apply_message_styling(bufnr, role, content_start, content_end)

  -- Apply thinking region styling
  if #thinking_regions > 0 then
    local thinking_ns = vim.api.nvim_create_namespace("cog_thinking")
    for _, region in ipairs(thinking_regions) do
      -- Adjust line numbers to buffer positions (account for border prefix in formatted lines)
      local header_buf_line = content_start + region.start_line - 1
      local end_buf_line = content_start + region.end_line - 1

      -- Style the thinking header line
      render_thinking_header(bufnr, header_buf_line)

      -- Apply dimmed styling to thinking content
      for line_idx = header_buf_line + 1, end_buf_line do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, thinking_ns, line_idx, 0, {
          end_row = line_idx,
          end_col = 0,
          line_hl_group = "CogThinkingContent",
          priority = 12,
        })
      end
    end
  end

  -- Track message block
  table.insert(state.message_blocks, {
    role = role,
    header_line = header_line,
    content_start = content_start,
    content_end = content_end,
  })

  state.last_role = role
  state.last_line = content_end + 1

  -- Scroll to bottom
  if state.layout_type == "popup" then
    if state.messages and state.messages.winid then
      vim.api.nvim_win_set_cursor(state.messages.winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
    end
  else
    split.scroll_to_bottom()
  end

  return {
    prefix_line = header_line + 1,
    content_start = content_start + 1,
    content_count = #formatted_lines,
  }
end

function M.begin_stream(role)
  if state.stream.active and state.stream.role == role and state.stream.anchor_line then
    return
  end
  M.end_stream()
  state.stream.active = true
  state.stream.role = role
  state.stream.kind = nil
end

local function append_stream_text(role, text)
  local bufnr = get_message_buf()
  local cfg = config.get().ui.chat or {}

  if not state.stream.active or state.stream.role ~= role or not state.stream.anchor_line then
    local meta = M.append(role, text)
    state.stream.active = true
    state.stream.role = role
    state.stream.anchor_line = meta.content_start + meta.content_count - 1
    state.stream.block_index = #state.message_blocks
    reset_stream_timer()
    return
  end

  local anchor_line = state.stream.anchor_line
  local current = vim.api.nvim_buf_get_lines(bufnr, anchor_line - 1, anchor_line, false)[1]
  if current == nil then
    local meta = M.append(role, text)
    state.stream.active = true
    state.stream.role = role
    state.stream.anchor_line = meta.content_start + meta.content_count - 1
    state.stream.block_index = #state.message_blocks
    reset_stream_timer()
    return
  end

  local parts = vim.split(tostring(text), "\n", { plain = true })

  -- Append first part to current line
  local first = current .. (parts[1] or "")
  vim.api.nvim_buf_set_lines(bufnr, anchor_line - 1, anchor_line, false, { first })

  -- Handle additional lines
  local extra_count = 0
  if #parts > 1 then
    local extra = {}
    local border = cfg.show_borders ~= false and (BORDER[role] or BORDER.system) .. " " or ""
    for i = 2, #parts do
      table.insert(extra, border .. parts[i])
    end
    vim.api.nvim_buf_set_lines(bufnr, anchor_line, anchor_line, false, extra)
    extra_count = #extra

    -- Apply styling to new lines
    local new_start = anchor_line
    local new_end = anchor_line + #extra - 1

    -- Use dimmed styling for thinking content, regular styling otherwise
    if state.stream.kind == "thought" then
      local thinking_ns = vim.api.nvim_create_namespace("cog_thinking")
      for line_idx = new_start, new_end do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, thinking_ns, line_idx, 0, {
          end_row = line_idx,
          end_col = 0,
          line_hl_group = "CogThinkingContent",
          priority = 12,
        })
      end
    else
      apply_message_styling(bufnr, role, new_start, new_end)
    end
  end

  -- Also apply thinking styling to the current anchor line (where content was appended)
  if state.stream.kind == "thought" then
    local thinking_ns = vim.api.nvim_create_namespace("cog_thinking")
    pcall(vim.api.nvim_buf_set_extmark, bufnr, thinking_ns, anchor_line - 1, 0, {
      end_row = anchor_line - 1,
      end_col = 0,
      line_hl_group = "CogThinkingContent",
      priority = 12,
    })
  end

  if extra_count > 0 then
    local old_anchor_line = anchor_line
    state.stream.anchor_line = anchor_line + extra_count

    local block_index = state.stream.block_index
    if block_index and state.message_blocks[block_index] then
      state.message_blocks[block_index].content_end =
        state.message_blocks[block_index].content_end + extra_count
    end

    shift_message_blocks_after(block_index, extra_count)

    if state.last_line then
      if state.last_line > old_anchor_line then
        state.last_line = state.last_line + extra_count
      elseif state.last_line == old_anchor_line and state.last_role == role then
        state.last_line = state.last_line + extra_count
      end
    end
  end

  reset_stream_timer()

  -- Scroll to bottom
  if state.layout_type == "popup" then
    if state.messages and state.messages.winid then
      vim.api.nvim_win_set_cursor(state.messages.winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
    end
  else
    split.scroll_to_bottom()
  end
end

local function close_thought_block()
  if state.stream.kind == "thought" then
    -- Add a dashed separator line after thinking content
    local cfg = config.get().ui.chat or {}
    local width = get_chat_width()
    -- Account for border character and space
    local separator_width = math.max(20, width - 4)
    local separator = string.rep("─ ", math.floor(separator_width / 2))
    append_stream_text(state.stream.role or "assistant", "\n" .. separator .. "\n\n")
    state.stream.kind = "message"
  end
end

local function open_thought_block()
  if state.stream.kind ~= "thought" then
    local bufnr = get_message_buf()
    local cfg = config.get().ui.chat or {}
    local show_borders = cfg.show_borders ~= false
    local border = show_borders and (BORDER.assistant .. " ") or ""

    -- Render styled thinking header
    local thinking_icon = icons.tool_icons.thinking or "󰠗"
    local header_text = thinking_icon .. " Thinking"

    -- Append header line, then manually insert an empty line for content
    append_stream_text(state.stream.role or "assistant", "\n" .. header_text)

    -- The anchor now points to the header line. Insert a new empty line after it
    -- for streaming content to flow into
    if state.stream.anchor_line and bufnr then
      -- Apply styling to the header line (anchor points to it)
      local header_line = state.stream.anchor_line - 1  -- 0-indexed
      if header_line >= 0 then
        render_thinking_header(bufnr, header_line)
      end

      -- Insert empty line after header for content streaming
      vim.api.nvim_buf_set_lines(bufnr, state.stream.anchor_line, state.stream.anchor_line, false, { border })
      state.stream.anchor_line = state.stream.anchor_line + 1

      -- Update message block tracking
      local block_index = state.stream.block_index
      if block_index and state.message_blocks[block_index] then
        state.message_blocks[block_index].content_end =
          state.message_blocks[block_index].content_end + 1
      end
    end

    state.stream.kind = "thought"
  end
end

function M.append_stream(role, text)
  append_stream_text(role, text)
end

function M.append_stream_chunk(role, text, kind)
  local normalized = normalize_stream_kind(kind)
  if normalized == "thought" then
    open_thought_block()
  else
    close_thought_block()
  end
  append_stream_text(role, text)
end

-- Display token count as virtual text at end of message block
local function display_token_count(tokens, block_index)
  if not tokens or tokens <= 0 then
    return
  end

  local bufnr = get_message_buf()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local block = state.message_blocks[block_index]
  if not block then
    return
  end

  local ns = vim.api.nvim_create_namespace("cog_token_count")
  local line = block.content_end

  -- Format token count
  local token_str
  if tokens >= 1000 then
    token_str = string.format("%.1fk tokens", tokens / 1000)
  else
    token_str = string.format("%d tokens", tokens)
  end

  -- Add virtual text at end of line
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, 0, {
    virt_text = { { "[" .. token_str .. "]", "CogTokenCount" } },
    virt_text_pos = "eol",
    priority = 50,
  })
end

function M.end_stream(tokens)
  if not state.stream.active then
    return
  end
  close_thought_block()
  clear_stream_timer()

  -- Display token count if provided
  if tokens and tokens > 0 and state.stream.block_index then
    display_token_count(tokens, state.stream.block_index)
  end

  state.stream.active = false
  state.stream.role = nil
  state.stream.anchor_line = nil
  state.stream.block_index = nil
  state.stream.kind = nil
  state.current_message_tokens = 0
end

-- Set token count for current message (can be called during streaming)
function M.set_message_tokens(tokens)
  state.current_message_tokens = tokens or 0
end

-- Tool card rendering helpers
local function get_tool_icon_hl(kind)
  if not kind then
    return "CogToolIcon"
  end
  local normalized = kind:lower()
  if normalized == "read" then
    return "CogToolIconRead"
  elseif normalized == "write" then
    return "CogToolIconWrite"
  elseif normalized == "edit" then
    return "CogToolIconEdit"
  elseif normalized == "bash" or normalized == "execute" or normalized == "terminal" then
    return "CogToolIconBash"
  elseif normalized == "grep" or normalized == "glob" or normalized == "find" then
    return "CogToolIconSearch"
  elseif normalized == "web" or normalized == "fetch" or normalized == "webfetch" then
    return "CogToolIconWeb"
  elseif normalized == "task" or normalized == "agent" then
    return "CogToolIconTask"
  end
  return "CogToolIcon"
end

-- Returns all lines plus fold info if content exceeds max_lines
-- Foldtext will display our custom indicator when the fold is closed
-- Returns: lines, fold_info (start line index, end line index, hidden count)
local function prepare_foldable_lines(lines, max_lines)
  if not lines or #lines <= max_lines then
    return lines, nil
  end

  -- Return all lines - the fold mechanism will hide the excess
  local hidden_count = #lines - max_lines + 1
  local fold_start = max_lines - 1 -- 0-indexed, first line to be folded

  return lines, {
    fold_start = fold_start,
    fold_end = #lines - 1,
    hidden_count = hidden_count,
  }
end

-- Legacy function for backward compatibility
local function truncate_lines(lines, max_lines)
  if not lines or #lines <= max_lines then
    return lines, false
  end
  local result = {}
  for i = 1, max_lines - 1 do
    table.insert(result, lines[i])
  end
  table.insert(result, string.format("... (%d more lines)", #lines - max_lines + 1))
  return result, true
end

-- Get the accent bar character based on status
local function get_accent_bar(status)
  local is_error = status and (status:lower() == "failed" or status:lower() == "error")
  return is_error and "╏" or "┃"
end

-- Render tool card from structured data using left accent bar style
-- tool_data = { kind, title, status, command, output, locations, cwd, exit_code, diff }
local function render_tool_card_lines(tool_data)
  local cfg = config.get().ui.tool_calls or {}
  local show_icons = cfg.icons ~= false
  local max_preview = cfg.max_preview_lines or 8
  local show_borders = (config.get().ui.chat or {}).show_borders ~= false

  local status = tool_data.status
  local kind = tool_data.kind
  local accent = get_accent_bar(status)

  -- Message border prefix (to nest inside assistant message)
  local msg_border = show_borders and (BORDER.assistant .. " ") or ""

  -- Build header with tool type
  local tool_icon = show_icons and icons.get_tool_icon(kind) or ""
  local status_icon, _ = icons.get_status_icon(status)

  -- Capitalize kind for display, fallback to "Tool"
  local display_kind = kind and (kind:sub(1,1):upper() .. kind:sub(2)) or "Tool"

  -- Build summary for header (command or first location)
  local summary = ""
  if tool_data.command and tool_data.command ~= "" then
    -- Truncate command if too long
    summary = tool_data.command
    if #summary > 40 then
      summary = summary:sub(1, 37) .. "..."
    end
  elseif tool_data.locations and #tool_data.locations > 0 then
    -- Show first location for read/write operations
    local loc = tool_data.locations[1]
    summary = loc:match("([^/]+)$") or loc
    if #tool_data.locations > 1 then
      summary = summary .. string.format(" +%d more", #tool_data.locations - 1)
    end
  end

  local lines = {}

  -- Header line: accent | icon kind status_icon  summary
  local header_parts = {}
  if show_icons and tool_icon ~= "" then
    table.insert(header_parts, tool_icon)
  end
  table.insert(header_parts, display_kind)
  if status_icon then
    table.insert(header_parts, status_icon)
  end
  if summary ~= "" then
    table.insert(header_parts, " " .. summary)
  end

  local header_line = msg_border .. accent .. "  " .. table.concat(header_parts, " ")
  table.insert(lines, header_line)

  -- Collect content lines
  local content_lines = {}

  -- Show locations if present (for read operations with multiple files)
  if tool_data.locations and #tool_data.locations > 1 then
    for _, loc in ipairs(tool_data.locations) do
      -- Show just filename for brevity
      local filename = loc:match("([^/]+)$") or loc
      table.insert(content_lines, filename)
    end
  end

  -- Show diff if present
  if tool_data.diff and tool_data.diff ~= "" then
    for line in tool_data.diff:gmatch("[^\n]+") do
      if line ~= "" then
        table.insert(content_lines, line)
      end
    end
  end

  -- Show output if present and completed
  if tool_data.output and tool_data.output ~= "" and status == "completed" then
    for line in tool_data.output:gmatch("[^\n]+") do
      if line ~= "" then
        table.insert(content_lines, line)
      end
    end
  elseif status == "in_progress" then
    table.insert(content_lines, "...")
  end

  -- Track fold information
  local fold_info = nil
  local content_start_in_card = #lines -- Index where content starts (after header)

  -- Prepare foldable content if needed
  if #content_lines > 0 then
    local prepared_lines, fold_data = prepare_foldable_lines(content_lines, max_preview)
    for _, content_line in ipairs(prepared_lines) do
      -- Truncate long lines (wider allowed since no right border)
      if #content_line > 70 then
        content_line = content_line:sub(1, 67) .. "..."
      end
      -- Add with accent bar prefix (indented under header)
      table.insert(lines, msg_border .. accent .. "    " .. content_line)
    end

    -- Convert fold info to absolute positions within card
    if fold_data then
      fold_info = {
        -- fold_start is relative to content, convert to relative to card lines
        fold_start = content_start_in_card + fold_data.fold_start,
        fold_end = content_start_in_card + fold_data.fold_end,
        hidden_count = fold_data.hidden_count,
      }
    end
  end

  return lines, fold_info
end

-- Get the highlight group for the accent bar based on status
local function get_accent_bar_hl(status)
  if not status then
    return "CogToolAccentBar"
  end
  local normalized = status:lower():gsub("[%s%-]", "_")
  if normalized == "completed" or normalized == "success" or normalized == "done" then
    return "CogToolAccentBarSuccess"
  elseif normalized == "failed" or normalized == "error" then
    return "CogToolAccentBarError"
  elseif normalized == "pending" or normalized == "in_progress" or normalized == "running" then
    return "CogToolAccentBarPending"
  end
  return "CogToolAccentBar"
end

local function apply_tool_card_highlights(bufnr, start_line, lines, status, kind)
  local ns = vim.api.nvim_create_namespace("cog_tool_card")
  local accent_hl = get_accent_bar_hl(status)
  local icon_hl = get_tool_icon_hl(kind)
  local _, status_hl = icons.get_status_icon(status)

  for i, line in ipairs(lines) do
    local line_idx = start_line + i - 1

    -- Find the accent bar character position (after message border)
    local accent_start = line:find("[┃╏]")
    if accent_start then
      -- Highlight the accent bar character
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, accent_start - 1, {
        end_row = line_idx,
        end_col = accent_start + 2,  -- UTF-8 character is 3 bytes
        hl_group = accent_hl,
        priority = 20,
      })
    end

    -- Highlight the header line (first line with icon and title)
    if i == 1 then
      -- Find and highlight the tool icon (first non-space/bar character after accent)
      local content_start = accent_start and accent_start + 4 or 0
      local icon_match_start = line:find("[^%s┃╏│]", content_start)
      if icon_match_start then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, icon_match_start - 1, {
          end_row = line_idx,
          end_col = icon_match_start + 3,  -- Icon is typically 3-4 bytes
          hl_group = icon_hl,
          priority = 25,
        })
      end

      -- Find and highlight status icon
      local status_icon, _ = icons.get_status_icon(status)
      if status_icon then
        local status_pos = line:find(status_icon, 1, true)
        if status_pos then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, status_pos - 1, {
            end_row = line_idx,
            end_col = status_pos + #status_icon,
            hl_group = status_hl,
            priority = 25,
          })
        end
      end

      -- Apply header styling to the tool name
      local display_kind = kind and (kind:sub(1,1):upper() .. kind:sub(2)) or "Tool"
      local kind_pos = line:find(display_kind, 1, true)
      if kind_pos then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, kind_pos - 1, {
          end_row = line_idx,
          end_col = kind_pos + #display_kind - 1,
          hl_group = "CogToolCardHeader",
          priority = 22,
        })
      end
    end

    -- Diff highlighting - detect diff content in tool card lines
    -- Strip accent bar and spaces first to get content
    local content = line:gsub("^[│┃╏%s]+", "")

    -- Hunk headers (@@ ... @@)
    if content:match("^@@.*@@") then
      local content_start = line:find("@@")
      if content_start then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, content_start - 1, {
          end_row = line_idx,
          end_col = #line,
          hl_group = "CogDiffHunk",
          priority = 30,
        })
      end
    -- Added lines (+...)
    elseif content:match("^%+[^%+]") or content:match("^%+$") then
      local content_start = line:find("%+")
      if content_start then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, content_start - 1, {
          end_row = line_idx,
          end_col = #line,
          hl_group = "CogDiffAdd",
          priority = 30,
        })
      end
    -- Deleted lines (-...)
    elseif content:match("^%-[^%-]") or content:match("^%-$") then
      local content_start = line:find("%-")
      if content_start then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, content_start - 1, {
          end_row = line_idx,
          end_col = #line,
          hl_group = "CogDiffDelete",
          priority = 30,
        })
      end
    end
  end
end

-- upsert_tool_call now accepts structured tool_data
-- tool_data = { kind, title, status, command, output, locations, cwd, exit_code }
-- state.tool_calls stores { index = block_index, kind = kind } to persist kind across updates
function M.upsert_tool_call(tool_call_id, tool_data)
  local cfg = config.get().ui.tool_calls or {}
  local style = cfg.style or "card"

  local status = tool_data.status
  local kind = tool_data.kind
  local title = tool_data.title

  -- Retrieve stored kind if current kind is nil (updates often don't include kind)
  local stored = tool_call_id and state.tool_calls[tool_call_id]
  if stored and type(stored) == "table" and not kind then
    kind = stored.kind
    tool_data.kind = kind  -- Update tool_data so render function has it
  end

  -- For minimal or inline styles, fall back to simple rendering
  if style ~= "card" then
    local role = "system"
    local header = string.format("Tool: %s", title or "Tool")
    local simple_lines = { header }
    if status and status ~= "" then
      table.insert(simple_lines, string.format("Status: %s", status))
    end
    if tool_data.command then
      table.insert(simple_lines, "$ " .. tool_data.command)
    end
    if tool_data.output and status == "completed" then
      table.insert(simple_lines, "")
      for line in tool_data.output:gmatch("[^\n]+") do
        table.insert(simple_lines, line)
      end
    end

    local block_index = stored and (type(stored) == "table" and stored.index or stored) or nil
    if block_index and state.message_blocks[block_index] then
      replace_message_block(block_index, "system", simple_lines)
    else
      M.append("system", table.concat(simple_lines, "\n"))
      if tool_call_id then
        state.tool_calls[tool_call_id] = { index = #state.message_blocks, kind = kind }
      end
    end

    -- Scroll to bottom
    if state.layout_type == "popup" then
      if state.messages and state.messages.winid then
        vim.api.nvim_win_set_cursor(state.messages.winid, { vim.api.nvim_buf_line_count(get_message_buf()), 0 })
      end
    else
      split.scroll_to_bottom()
    end
    return
  end

  -- Card style rendering
  local card_lines, fold_info = render_tool_card_lines(tool_data)

  local block_index = stored and (type(stored) == "table" and stored.index or stored) or nil
  local bufnr = get_message_buf()

  if block_index and state.message_blocks[block_index] then
    -- Update existing tool call
    local block = state.message_blocks[block_index]
    local old_count = block.content_end - block.content_start + 1
    local new_count = #card_lines

    vim.api.nvim_buf_set_lines(bufnr, block.content_start, block.content_end + 1, false, card_lines)

    local delta = new_count - old_count
    if delta ~= 0 then
      block.content_end = block.content_end + delta
      shift_message_blocks_after(block_index, delta)

      if state.last_line then
        local last_zero_based = state.last_line - 1
        if last_zero_based > block.content_end - delta then
          state.last_line = state.last_line + delta
        end
      end
    end

    -- Clear old highlights and apply new ones
    local ns = vim.api.nvim_create_namespace("cog_tool_card")
    vim.api.nvim_buf_clear_namespace(bufnr, ns, block.content_start, block.content_end + 1)
    apply_tool_card_highlights(bufnr, block.content_start, card_lines, status, kind)

    -- Create fold for long output if needed
    if fold_info and status == "completed" then
      local fold_start = block.content_start + fold_info.fold_start
      local fold_end = block.content_start + fold_info.fold_end
      create_tool_fold(bufnr, fold_start, fold_end, fold_info.hidden_count)
    end
  else
    -- Create new tool call block
    local existing = vim.api.nvim_buf_line_count(bufnr)
    local chat_cfg = config.get().ui.chat or {}
    local message_padding = chat_cfg.message_padding or 1

    -- Add padding before (except for first message)
    local padding_lines = {}
    if existing > 1 then
      for _ = 1, message_padding do
        table.insert(padding_lines, "")
      end
    end

    local padding_start = existing
    local content_start = padding_start + #padding_lines
    local content_end = content_start + #card_lines - 1

    if #padding_lines > 0 then
      vim.api.nvim_buf_set_lines(bufnr, padding_start, padding_start, false, padding_lines)
    end
    vim.api.nvim_buf_set_lines(bufnr, content_start, content_start, false, card_lines)

    -- Apply highlights
    apply_tool_card_highlights(bufnr, content_start, card_lines, status, kind)

    -- Create fold for long output if needed
    if fold_info and status == "completed" then
      local fold_start = content_start + fold_info.fold_start
      local fold_end = content_start + fold_info.fold_end
      create_tool_fold(bufnr, fold_start, fold_end, fold_info.hidden_count)
    end

    -- Track message block (no header for tool cards)
    table.insert(state.message_blocks, {
      role = "tool",
      header_line = content_start,  -- No separate header
      content_start = content_start,
      content_end = content_end,
    })

    if tool_call_id then
      state.tool_calls[tool_call_id] = { index = #state.message_blocks, kind = kind }
    end

    state.last_line = content_end + 1
  end

  -- Scroll to bottom
  if state.layout_type == "popup" then
    if state.messages and state.messages.winid then
      vim.api.nvim_win_set_cursor(state.messages.winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
    end
  else
    split.scroll_to_bottom()
  end
end

function M.append_chunk(role, text)
  local bufnr = get_message_buf()
  local cfg = config.get().ui.chat or {}
  local show_borders = cfg.show_borders ~= false

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

  -- Append first part to current line
  local first = current .. (parts[1] or "")
  vim.api.nvim_buf_set_lines(bufnr, state.last_line - 1, state.last_line, false, { first })

  -- Handle additional lines
  if #parts > 1 then
    local extra = {}
    local border = show_borders and (BORDER[role] or BORDER.system) .. " " or ""
    for i = 2, #parts do
      table.insert(extra, border .. parts[i])
    end
    vim.api.nvim_buf_set_lines(bufnr, state.last_line, state.last_line, false, extra)

    -- Apply styling to new lines
    local new_start = state.last_line
    local new_end = state.last_line + #extra - 1
    apply_message_styling(bufnr, role, new_start, new_end)

    -- Update last message block if exists
    if #state.message_blocks > 0 then
      state.message_blocks[#state.message_blocks].content_end = new_end
    end

    state.last_line = state.last_line + #extra
  end

  -- Scroll to bottom
  if state.layout_type == "popup" then
    if state.messages and state.messages.winid then
      vim.api.nvim_win_set_cursor(state.messages.winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
    end
  else
    split.scroll_to_bottom()
  end
end

function M.begin_pending()
  local cfg = config.get().ui.chat or {}
  if state.pending.active then
    return
  end

  -- Save current message state before appending pending message
  state.pending.saved_last_role = state.last_role
  state.pending.saved_last_line = state.last_line

  local meta = M.append("system", cfg.pending_message or "Thinking...")
  state.pending.active = true
  -- Include the padding line in the range (it's at prefix_line - 2 if there was padding)
  local range_start = meta.prefix_line - 1
  -- Check if there was a padding line before the header
  local bufnr = get_message_buf()
  if range_start > 0 then
    local prev_line = vim.api.nvim_buf_get_lines(bufnr, range_start - 1, range_start, false)[1]
    if prev_line == "" then
      range_start = range_start - 1
    end
  end
  state.pending.range = {
    start = range_start,
    finish = (meta.content_start - 1) + meta.content_count,
  }

  if cfg.disable_input_while_waiting ~= false then
    set_input_locked(true)
  end

  -- Update status indicator
  if state.layout_type ~= "popup" then
    split.set_status("pending", "Thinking...")
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
  local lines_deleted = 0
  if range and vim.api.nvim_buf_is_valid(bufnr) then
    local start = math.max(range.start, 0)
    local finish = math.max(range.finish or start, start)
    if finish > start then
      lines_deleted = finish - start
      pcall(vim.api.nvim_buf_set_lines, bufnr, start, finish, false, {})
    end
  end

  state.pending.active = false
  state.pending.range = nil

  -- Restore message state from before pending was shown
  -- This ensures streaming chunks continue from the correct position
  state.last_role = state.pending.saved_last_role
  state.last_line = state.pending.saved_last_line
  state.pending.saved_last_role = nil
  state.pending.saved_last_line = nil

  set_input_locked(false)

  -- Update status indicator
  if state.layout_type ~= "popup" then
    split.set_status("ok", "Ready")
  end
end

function M.is_pending()
  return state.pending.active
end

function M.is_open()
  if state.layout_type == "popup" then
    return state.layout ~= nil and popup_buf_valid(state.messages)
  else
    return split.is_open()
  end
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

function M.close()
  if state.layout_type == "popup" and state.layout then
    pcall(function()
      state.layout:unmount()
    end)
    state.layout = nil
    state.messages = nil
    state.input = nil
  else
    split.close()
  end
end

-- Reset all state for a new conversation
function M.reset()
  state.last_role = nil
  state.last_line = nil
  state.message_blocks = {}
  state.tool_calls = {}
  state.current_message_tokens = 0

  -- Clear fold ranges
  fold_ranges = {}

  M.end_stream()

  -- Clear pending state
  if state.pending.timer then
    state.pending.timer:stop()
    state.pending.timer:close()
    state.pending.timer = nil
  end
  state.pending.active = false
  state.pending.range = nil

  -- Clear buffer content
  local bufnr = get_message_buf()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    -- Clear extmarks
    local ns = vim.api.nvim_create_namespace("cog_chat_styling")
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    -- Clear tool card highlights
    local tool_ns = vim.api.nvim_create_namespace("cog_tool_card")
    vim.api.nvim_buf_clear_namespace(bufnr, tool_ns, 0, -1)
    -- Clear token count
    local token_ns = vim.api.nvim_create_namespace("cog_token_count")
    vim.api.nvim_buf_clear_namespace(bufnr, token_ns, 0, -1)
    -- Clear thinking highlights
    local thinking_ns = vim.api.nvim_create_namespace("cog_thinking")
    vim.api.nvim_buf_clear_namespace(bufnr, thinking_ns, 0, -1)
    -- Clear all folds
    pcall(vim.api.nvim_buf_call, bufnr, function()
      vim.cmd("normal! zE")
    end)
  end
end

-- Update status indicator with tool information
-- opts = { tool_name = "Read", tool_kind = "read", command = "ls -la" }
function M.set_tool_status(status, opts)
  opts = opts or {}
  if state.layout_type ~= "popup" then
    if status == "running" or status == "in_progress" then
      split.set_status("tool_running", nil, opts)
    elseif status == "completed" then
      split.set_status("ok", "Ready")
    elseif status == "failed" or status == "error" then
      split.set_status("error", opts.message or "Tool failed")
    else
      split.set_status("pending", nil, opts)
    end
  end
end

-- Test helper: return message buffer id
function M._get_message_buf()
  return get_message_buf()
end

return M
