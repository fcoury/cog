local M = {}

function M.read(path)
  if not path or path == "" then
    return ""
  end

  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, "\n")
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return ""
  end

  return table.concat(lines, "\n")
end

function M.write(path, content)
  if not path or path == "" then
    return false, "missing path"
  end

  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
  end

  local lines = vim.split(content or "", "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return true, nil
end

return M
