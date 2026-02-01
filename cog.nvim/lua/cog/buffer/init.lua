local M = {}

local tracker = require("cog.buffer.tracker")
local apply = require("cog.buffer.apply")

function M.read(path)
  if not path or path == "" then
    return ""
  end

  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    tracker.record_read(path, content)
    return content
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return ""
  end

  local content = table.concat(lines, "\n")
  tracker.record_read(path, content)
  return content
end

function M.write(path, content)
  return apply.apply(path, content or "")
end

return M
