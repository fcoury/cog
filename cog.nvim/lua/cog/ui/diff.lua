local M = {}

local function create_scratch(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function open_diff_tab(old_text, new_text)
  local prev_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("tabnew")

  local old_buf = create_scratch(vim.split(old_text, "\n", { plain = true }))
  vim.api.nvim_win_set_buf(0, old_buf)

  vim.cmd("vsplit")
  local new_buf = create_scratch(vim.split(new_text, "\n", { plain = true }))
  vim.api.nvim_win_set_buf(0, new_buf)

  vim.cmd("windo diffthis")

  return prev_tab
end

function M.show_diff(path, old_text, new_text)
  local prev_tab = open_diff_tab(old_text, new_text)
  local choice = vim.fn.confirm("Apply changes to " .. path .. "?", "&Yes\n&No", 2)
  vim.cmd("tabclose")
  if prev_tab and vim.api.nvim_tabpage_is_valid(prev_tab) then
    vim.api.nvim_set_current_tabpage(prev_tab)
  end
  return choice == 1
end

function M.show_conflict(path, base_text, ours_text, new_text)
  vim.notify("Conflict detected for " .. path .. ". Review required.", vim.log.levels.WARN)
  local prev_tab = open_diff_tab(ours_text, new_text)
  vim.fn.confirm("Conflict: close diff view", "&Close", 1)
  vim.cmd("tabclose")
  if prev_tab and vim.api.nvim_tabpage_is_valid(prev_tab) then
    vim.api.nvim_set_current_tabpage(prev_tab)
  end
  return false
end

return M
