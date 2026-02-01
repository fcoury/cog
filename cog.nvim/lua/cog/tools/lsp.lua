local M = {}

local function get_bufnr(path)
  if path then
    local bufnr = vim.fn.bufnr(path)
    if bufnr == -1 then
      bufnr = vim.fn.bufadd(path)
      vim.fn.bufload(bufnr)
    end
    return bufnr
  end
  return vim.api.nvim_get_current_buf()
end

local function get_position(bufnr, pos)
  if pos and pos.line and pos.character then
    return { line = pos.line, character = pos.character }
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  return { line = cursor[1] - 1, character = cursor[2] }
end

function M.rename(params)
  local bufnr = get_bufnr(params.path)
  local position = get_position(bufnr, params.position)
  local new_name = params.new_name or params.name
  if not new_name then
    error("rename requires new_name")
  end

  local result = vim.lsp.buf_request_sync(
    bufnr,
    "textDocument/rename",
    {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      position = position,
      newName = new_name,
    },
    10000
  )

  local applied = 0
  if result then
    for client_id, resp in pairs(result) do
      if resp and resp.result then
        local edit = resp.result
        local client = vim.lsp.get_client_by_id(client_id)
        local encoding = client and client.offset_encoding or "utf-16"
        vim.lsp.util.apply_workspace_edit(edit, encoding)
        applied = applied + 1
      end
    end
  end

  return { applied = applied }
end

function M.code_action(params)
  local bufnr = get_bufnr(params.path)
  local position = get_position(bufnr, params.position)
  local range = params.range or { start = position, ["end"] = position }
  local context = params.context or { diagnostics = {} }

  local result = vim.lsp.buf_request_sync(
    bufnr,
    "textDocument/codeAction",
    {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      range = range,
      context = context,
    },
    10000
  )

  local applied = 0
  if result then
    for client_id, resp in pairs(result) do
      if resp and resp.result then
        local actions = resp.result
        local client = vim.lsp.get_client_by_id(client_id)
        local encoding = client and client.offset_encoding or "utf-16"
        for _, action in ipairs(actions) do
          if action.edit then
            vim.lsp.util.apply_workspace_edit(action.edit, encoding)
            applied = applied + 1
          end
          if action.command then
            vim.lsp.buf.execute_command(action.command)
          end
        end
      end
    end
  end

  return { applied = applied }
end

return M
