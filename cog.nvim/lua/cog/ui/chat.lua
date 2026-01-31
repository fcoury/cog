local M = {}

local state = {
  bufnr = nil,
  winid = nil,
}

local function ensure_buffer()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    return state.bufnr
  end

  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(state.bufnr, "bufhidden", "wipe")
  return state.bufnr
end

function M.open()
  local bufnr = ensure_buffer()

  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    return
  end

  vim.cmd("vsplit")
  state.winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.winid, bufnr)
end

function M.append(role, text)
  local bufnr = ensure_buffer()

  if not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
    M.open()
  end

  local prefix = role == "user" and "User:" or role == "assistant" and "Assistant:" or "Cog:"
  local lines = {}
  for line in tostring(text):gmatch("[^\n]*\n?") do
    if line == "" then
      break
    end
    table.insert(lines, line:gsub("\n$", ""))
  end

  if #lines == 0 then
    lines = { tostring(text) }
  end

  local existing = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, existing, existing, false, { prefix })
  vim.api.nvim_buf_set_lines(bufnr, existing + 1, existing + 1, false, lines)

  vim.api.nvim_win_set_cursor(state.winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
end

return M
