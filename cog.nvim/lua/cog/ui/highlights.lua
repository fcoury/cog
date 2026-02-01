local M = {}

function M.setup()
  -- Message headers (existing)
  vim.api.nvim_set_hl(0, "CogChatUserHeader", { link = "@markup.heading.2", default = true })
  vim.api.nvim_set_hl(0, "CogChatAssistantHeader", { link = "@markup.heading.2", default = true })
  vim.api.nvim_set_hl(0, "CogChatSystemHeader", { link = "@markup.heading.3", default = true })

  -- Tool status (existing - kept for backwards compatibility)
  vim.api.nvim_set_hl(0, "CogToolPending", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "CogToolSuccess", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "CogToolFailure", { link = "DiagnosticError", default = true })

  -- Tool card styling (Zed-inspired)
  vim.api.nvim_set_hl(0, "CogToolCardBorder", { fg = "#45475a", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardBorderSuccess", { fg = "#a6e3a1", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardBorderError", { fg = "#f38ba8", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardBorderPending", { fg = "#f9e2af", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardHeader", { fg = "#cdd6f4", bold = true, default = true })
  vim.api.nvim_set_hl(0, "CogToolCardHeaderBg", { bg = "#1e1e2e", default = true })

  -- Tool icons
  vim.api.nvim_set_hl(0, "CogToolIcon", { fg = "#cba6f7", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconRead", { fg = "#89b4fa", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconWrite", { fg = "#a6e3a1", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconEdit", { fg = "#f9e2af", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconBash", { fg = "#fab387", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconSearch", { fg = "#94e2d5", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconWeb", { fg = "#89dceb", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconTask", { fg = "#f5c2e7", default = true })

  -- Tool status icons
  vim.api.nvim_set_hl(0, "CogToolStatusPending", { fg = "#f9e2af", default = true })
  vim.api.nvim_set_hl(0, "CogToolStatusSuccess", { fg = "#a6e3a1", default = true })
  vim.api.nvim_set_hl(0, "CogToolStatusError", { fg = "#f38ba8", default = true })
  vim.api.nvim_set_hl(0, "CogToolStatusUnknown", { fg = "#6c7086", default = true })

  -- Tool card content
  vim.api.nvim_set_hl(0, "CogToolCardContent", { fg = "#a6adc8", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardMuted", { fg = "#6c7086", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardLabel", { fg = "#89b4fa", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardValue", { fg = "#cdd6f4", default = true })

  -- Tool card sections
  vim.api.nvim_set_hl(0, "CogToolSectionHeader", { fg = "#6c7086", italic = true, default = true })
  vim.api.nvim_set_hl(0, "CogToolSectionFold", { fg = "#45475a", default = true })

  -- Message content styling (OpenCode-inspired)
  vim.api.nvim_set_hl(0, "CogUserMessage", { default = true })
  vim.api.nvim_set_hl(0, "CogAssistantMessage", { default = true })
  vim.api.nvim_set_hl(0, "CogSystemMessage", { link = "Comment", default = true })

  -- Message borders
  vim.api.nvim_set_hl(0, "CogUserBorder", { fg = "#89b4fa", default = true })
  vim.api.nvim_set_hl(0, "CogAssistantBorder", { fg = "#a6adc8", default = true })
  vim.api.nvim_set_hl(0, "CogSystemBorder", { fg = "#f9e2af", default = true })

  -- Header/Footer
  vim.api.nvim_set_hl(0, "CogHeader", { link = "StatusLine", default = true })
  vim.api.nvim_set_hl(0, "CogHeaderTitle", { bold = true, default = true })
  vim.api.nvim_set_hl(0, "CogFooter", { link = "StatusLineNC", default = true })

  -- Status indicators
  vim.api.nvim_set_hl(0, "CogStatusOk", { fg = "#a6e3a1", default = true })
  vim.api.nvim_set_hl(0, "CogStatusPending", { fg = "#f9e2af", default = true })
  vim.api.nvim_set_hl(0, "CogStatusError", { fg = "#f38ba8", default = true })

  -- Input area
  vim.api.nvim_set_hl(0, "CogInputBorder", { fg = "#45475a", default = true })
  vim.api.nvim_set_hl(0, "CogInputPlaceholder", { fg = "#6c7086", italic = true, default = true })

  -- Separator line
  vim.api.nvim_set_hl(0, "CogSeparator", { fg = "#313244", default = true })
end

return M
