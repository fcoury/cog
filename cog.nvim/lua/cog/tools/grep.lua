local M = {}

local function build_command(params)
  local query = params.query or params.pattern
  if not query then
    error("grep requires query")
  end

  local root = params.root or vim.fn.getcwd()
  local cmd = { "rg", "--json", query, root }

  if params.glob then
    table.insert(cmd, "--glob")
    table.insert(cmd, params.glob)
  end

  if params.hidden then
    table.insert(cmd, "--hidden")
  end

  return cmd
end

function M.run(params)
  local cmd = build_command(params)
  local output = vim.fn.systemlist(cmd)
  local matches = {}

  for _, line in ipairs(output) do
    local ok, data = pcall(vim.json.decode, line)
    if ok and data and data.type == "match" then
      local match = data.data
      local path = match.path and match.path.text or ""
      local line_number = match.line_number or 0
      local submatches = match.submatches or {}
      local text = match.lines and match.lines.text or ""

      local columns = {}
      for _, sm in ipairs(submatches) do
        table.insert(columns, { start = sm.start, finish = sm['end'] })
      end

      table.insert(matches, {
        path = path,
        line = line_number,
        text = text,
        columns = columns,
      })
    end
  end

  return { matches = matches }
end

return M
