local M = {}

local grep = require("cog.tools.grep")
local apply_edits = require("cog.tools.apply_edits")
local lsp = require("cog.tools.lsp")

function M.dispatch(method, params)
  if method == "_cog.nvim/grep" then
    return grep.run(params)
  end
  if method == "_cog.nvim/apply_edits" then
    return apply_edits.run(params)
  end
  if method == "_cog.nvim/lsp/rename" then
    return lsp.rename(params)
  end
  if method == "_cog.nvim/lsp/code_action" then
    return lsp.code_action(params)
  end

  error("Unknown tool method: " .. tostring(method))
end

return M
