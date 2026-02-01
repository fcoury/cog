local M = {}

local buffer_apply = require("cog.buffer.apply")

local function apply_structured_edits(path, edits)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
  end

  -- Apply from end to start to keep offsets stable
  table.sort(edits, function(a, b)
    if a.start.line == b.start.line then
      return a.start.character > b.start.character
    end
    return a.start.line > b.start.line
  end)

  for _, edit in ipairs(edits) do
    local s = edit.start
    local e = edit["end"]
    vim.api.nvim_buf_set_text(
      bufnr,
      s.line,
      s.character,
      e.line,
      e.character,
      vim.split(edit.text or "", "\n", { plain = true })
    )
  end

  return true
end

function M.run(params)
  if params.path and (params.new_text or params.text) then
    return buffer_apply.apply(params.path, params.new_text or params.text)
  end

  if params.path and params.edits then
    apply_structured_edits(params.path, params.edits)
    return { ok = true }
  end

  error("apply_edits requires path + new_text or edits")
end

return M
