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
}

-- Message border characters
local BORDER = {
  user = "┃",
  assistant = "│",
  system = "┊",
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
  local icons = {
    user = cfg.user_icon or "●",
    assistant = cfg.assistant_icon or "◆",
    system = "○",
  }
  local names = {
    user = "You",
    assistant = "Assistant",
    system = "System",
  }
  local icon = icons[role] or icons.system
  local name = names[role] or "Cog"
  return icon .. " " .. name
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

function M.append(role, text)
  local bufnr = get_message_buf()
  local cfg = config.get().ui.chat or {}

  if should_auto_open() and state.messages == nil and (not state.winid or not vim.api.nvim_win_is_valid(state.winid)) then
    M.open()
  end

  -- Parse text into lines
  local raw_lines = split_lines(text)

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

  -- Apply content styling
  apply_message_styling(bufnr, role, content_start, content_end)

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
    apply_message_styling(bufnr, role, new_start, new_end)
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
    append_stream_text(state.stream.role or "assistant", "\n</thinking>\n")
    state.stream.kind = "message"
  end
end

local function open_thought_block()
  if state.stream.kind ~= "thought" then
    append_stream_text(state.stream.role or "assistant", "\n<thinking>\n")
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

function M.end_stream()
  if not state.stream.active then
    return
  end
  close_thought_block()
  clear_stream_timer()
  state.stream.active = false
  state.stream.role = nil
  state.stream.anchor_line = nil
  state.stream.block_index = nil
  state.stream.kind = nil
end

-- Tool card rendering helpers
local function get_tool_border_hl(status)
  if not status then
    return "CogToolCardBorder"
  end
  local normalized = status:lower():gsub("[%s%-]", "_")
  if normalized == "completed" or normalized == "success" or normalized == "done" then
    return "CogToolCardBorderSuccess"
  elseif normalized == "failed" or normalized == "error" then
    return "CogToolCardBorderError"
  elseif normalized == "pending" or normalized == "in_progress" or normalized == "running" then
    return "CogToolCardBorderPending"
  end
  return "CogToolCardBorder"
end

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

local function get_border_chars(status)
  local cfg = config.get().ui.tool_calls or {}
  local border_cfg = cfg.border or {}

  local is_error = status and (status:lower() == "failed" or status:lower() == "error")
  local chars = is_error and border_cfg.error or border_cfg.normal

  -- Fallback defaults
  if not chars then
    if is_error then
      chars = {
        top_left = "┌", top = "╌", top_right = "┐",
        left = "╎", right = "╎",
        bottom_left = "└", bottom = "╌", bottom_right = "┘",
        header_left = "├", header_right = "┤",
      }
    else
      chars = {
        top_left = "┌", top = "─", top_right = "┐",
        left = "│", right = "│",
        bottom_left = "└", bottom = "─", bottom_right = "┘",
        header_left = "├", header_right = "┤",
      }
    end
  end
  return chars
end

-- Render tool card from structured data
-- tool_data = { kind, title, status, command, output, locations, cwd, exit_code }
local function render_tool_card_lines(tool_data)
  local cfg = config.get().ui.tool_calls or {}
  local show_icons = cfg.icons ~= false
  local max_preview = cfg.max_preview_lines or 8

  local status = tool_data.status
  local kind = tool_data.kind
  local border = get_border_chars(status)
  local card_width = 55

  -- Build header with tool type
  local tool_icon = show_icons and icons.get_tool_icon(kind) or ""
  local status_icon, _ = icons.get_status_icon(status)

  -- Capitalize kind for display, fallback to "Tool"
  local display_kind = kind and (kind:sub(1,1):upper() .. kind:sub(2)) or "Tool"

  local header_content = show_icons
    and string.format(" %s %s ", tool_icon, display_kind)
    or string.format(" %s ", display_kind)

  local status_str = status_icon and string.format(" %s ", status_icon) or ""

  -- Calculate header width
  local header_len = vim.fn.strdisplaywidth(header_content)
  local status_len = vim.fn.strdisplaywidth(status_str)
  local fill_len = math.max(0, card_width - header_len - status_len - 2)
  local fill = string.rep(border.top, fill_len)

  local lines = {}

  -- Top border with tool type and status
  table.insert(lines, border.top_left .. border.top .. header_content .. fill .. status_str .. border.top_right)

  -- Collect content lines
  local content_lines = {}

  -- Show locations if present (for read operations)
  if tool_data.locations and #tool_data.locations > 0 then
    for _, loc in ipairs(tool_data.locations) do
      -- Show just filename for brevity
      local filename = loc:match("([^/]+)$") or loc
      table.insert(content_lines, filename)
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

  -- Truncate and add content lines with left border only
  if #content_lines > 0 then
    local truncated, was_truncated = truncate_lines(content_lines, max_preview)
    for _, content_line in ipairs(truncated) do
      -- Truncate long lines
      if #content_line > card_width - 4 then
        content_line = content_line:sub(1, card_width - 7) .. "..."
      end
      table.insert(lines, border.left .. "  " .. content_line)
    end
  end

  -- Bottom border
  local bottom_fill = string.rep(border.bottom, card_width + 1)
  table.insert(lines, border.bottom_left .. bottom_fill .. border.bottom_right)

  return lines
end

local function apply_tool_card_highlights(bufnr, start_line, lines, status, kind)
  local ns = vim.api.nvim_create_namespace("cog_tool_card")
  local border_hl = get_tool_border_hl(status)
  local icon_hl = get_tool_icon_hl(kind)
  local _, status_hl = icons.get_status_icon(status)

  for i, line in ipairs(lines) do
    local line_idx = start_line + i - 1

    -- Apply border highlight to border characters
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, 0, {
      end_row = line_idx,
      end_col = 0,
      line_hl_group = "CogToolCardContent",
      priority = 10,
    })

    -- Highlight border characters
    local first_char = line:sub(1, 3)
    if first_char:match("[┌└├│╎]") then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, 0, {
        end_row = line_idx,
        end_col = 3,
        hl_group = border_hl,
        priority = 20,
      })
    end

    -- Highlight the header line (first line with icon and title)
    if i == 1 then
      -- Find and highlight the tool icon
      local icon_start = line:find("[^ ─┌╌]", 2)
      if icon_start then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, icon_start - 1, {
          end_row = line_idx,
          end_col = icon_start + 4,
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
            end_col = status_pos + #status_icon + 1,
            hl_group = status_hl,
            priority = 25,
          })
        end
      end
    end

    -- Highlight section headers (Input, Output)
    if line:match("├.*Input") or line:match("├.*Output") then
      local section_start = line:find("[IO]")
      if section_start then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_idx, section_start - 1, {
          end_row = line_idx,
          end_col = section_start + 6,
          hl_group = "CogToolSectionHeader",
          priority = 25,
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
  local card_lines = render_tool_card_lines(tool_data)

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
  end
end

return M
