local M = {}

local state = {
  last_read = {},
}

function M.record_read(path, content)
  if not path or path == "" then
    return
  end
  state.last_read[path] = content
end

function M.get_last_read(path)
  return state.last_read[path]
end

return M
