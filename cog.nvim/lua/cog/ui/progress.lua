local M = {}

local handle = nil

function M.start(message)
  local ok, fidget = pcall(require, "fidget")
  if ok then
    handle = fidget.progress.handle.create({
      title = "Cog",
      message = message,
      lsp_client = { name = "cog" },
    })
  else
    vim.notify(message, vim.log.levels.INFO)
  end
end

function M.finish(message)
  if handle then
    handle:report({ message = message or "done" })
    handle:finish()
    handle = nil
  else
    if message then
      vim.notify(message, vim.log.levels.INFO)
    end
  end
end

return M
