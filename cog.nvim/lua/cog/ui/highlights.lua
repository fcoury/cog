local M = {}

function M.setup()
  vim.api.nvim_set_hl(0, "CogChatUserHeader", { link = "@markup.heading.2", default = true })
  vim.api.nvim_set_hl(0, "CogChatAssistantHeader", { link = "@markup.heading.2", default = true })
  vim.api.nvim_set_hl(0, "CogChatSystemHeader", { link = "@markup.heading.3", default = true })
  vim.api.nvim_set_hl(0, "CogToolPending", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "CogToolSuccess", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "CogToolFailure", { link = "DiagnosticError", default = true })
end

return M
