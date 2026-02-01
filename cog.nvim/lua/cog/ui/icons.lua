-- Tool icons mapping (Nerd Font icons)
local M = {}

-- Tool kind to icon mapping (inspired by Zed's IconName::Tool* pattern)
M.tool_icons = {
  -- File operations
  read = "",           -- nf-fa-file_text_o
  Read = "",
  write = "",          -- nf-fa-pencil_square_o
  Write = "",
  edit = "",           -- nf-fa-edit
  Edit = "",
  delete = "",         -- nf-fa-trash_o
  Delete = "",
  move = "󰁔",           -- nf-md-file_move
  Move = "󰁔",

  -- Search operations
  grep = "",           -- nf-fa-search
  Grep = "",
  glob = "",           -- nf-fa-folder_open_o
  Glob = "",
  find = "",
  Find = "",

  -- Terminal/execution
  bash = "",           -- nf-fa-terminal
  Bash = "",
  execute = "",
  Execute = "",
  terminal = "",
  Terminal = "",

  -- Web operations
  web = "󰖟",            -- nf-md-web
  Web = "󰖟",
  fetch = "󰖟",
  Fetch = "󰖟",
  WebFetch = "󰖟",

  -- Agent/task operations
  task = "",           -- nf-fa-tasks
  Task = "",
  agent = "",          -- nf-fa-user_secret
  Agent = "",
  subagent = "",

  -- Thinking/reasoning
  think = "󰠗",          -- nf-md-head_lightbulb
  Think = "󰠗",
  thinking = "󰠗",
  Thinking = "󰠗",

  -- LSP operations
  lsp = "",            -- nf-fa-code
  Lsp = "",
  LSP = "",

  -- Notebook
  notebook = "",       -- nf-fa-book
  Notebook = "",
  NotebookEdit = "",

  -- MCP
  mcp = "󰣀",            -- nf-md-connection
  Mcp = "󰣀",
  MCP = "󰣀",
}

-- Status icons
M.status_icons = {
  pending = "◐",
  in_progress = "◐",
  running = "◐",
  completed = "✓",
  success = "✓",
  done = "✓",
  failed = "✗",
  error = "✗",
  cancelled = "○",
  canceled = "○",
  unknown = "?",
}

-- Spinner frames for animation
M.spinner_frames = { "◐", "◓", "◑", "◒" }

-- Default/fallback icon
M.default_tool_icon = "󰭻"  -- nf-md-hammer_wrench

--- Get icon for a tool kind
---@param kind string|nil Tool kind/type
---@return string icon
function M.get_tool_icon(kind)
  if not kind then
    return M.default_tool_icon
  end
  return M.tool_icons[kind] or M.default_tool_icon
end

--- Get icon for a status
---@param status string|nil Tool status
---@return string icon, string hl_group
function M.get_status_icon(status)
  if not status then
    return M.status_icons.unknown, "CogToolStatusUnknown"
  end

  local normalized = status:lower():gsub("[%s%-]", "_")
  local icon = M.status_icons[normalized] or M.status_icons.unknown

  local hl_group
  if normalized == "completed" or normalized == "success" or normalized == "done" then
    hl_group = "CogToolStatusSuccess"
  elseif normalized == "failed" or normalized == "error" then
    hl_group = "CogToolStatusError"
  elseif normalized == "pending" or normalized == "in_progress" or normalized == "running" then
    hl_group = "CogToolStatusPending"
  else
    hl_group = "CogToolStatusUnknown"
  end

  return icon, hl_group
end

--- Get next spinner frame
---@param current_frame number Current frame index (1-based)
---@return string frame, number next_index
function M.get_spinner_frame(current_frame)
  local idx = current_frame or 1
  local frame = M.spinner_frames[idx] or M.spinner_frames[1]
  local next_idx = (idx % #M.spinner_frames) + 1
  return frame, next_idx
end

return M
