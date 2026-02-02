local M = {}

function M.setup()
  -- Message headers - link to standard markup headings
  vim.api.nvim_set_hl(0, "CogChatUserHeader", { link = "@markup.heading.2", default = true })
  vim.api.nvim_set_hl(0, "CogChatAssistantHeader", { link = "@markup.heading.2", default = true })
  vim.api.nvim_set_hl(0, "CogChatSystemHeader", { link = "@markup.heading.3", default = true })

  -- Tool status - use standard diagnostic colors
  vim.api.nvim_set_hl(0, "CogToolPending", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "CogToolSuccess", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "CogToolFailure", { link = "DiagnosticError", default = true })

  -- Tool card borders - use standard border/diagnostic colors (legacy)
  vim.api.nvim_set_hl(0, "CogToolCardBorder", { link = "FloatBorder", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardBorderSuccess", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardBorderError", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardBorderPending", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardHeaderBg", { link = "NormalFloat", default = true })

  -- Tool accent bar - left vertical bar indicating tool region (new minimal style)
  vim.api.nvim_set_hl(0, "CogToolAccentBar", { link = "FloatBorder", default = true })
  vim.api.nvim_set_hl(0, "CogToolAccentBarSuccess", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "CogToolAccentBarError", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "CogToolAccentBarPending", { link = "DiagnosticWarn", default = true })

  -- Tool icons - use standard syntax and diagnostic colors
  vim.api.nvim_set_hl(0, "CogToolIcon", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconRead", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconWrite", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconEdit", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconBash", { link = "Constant", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconSearch", { link = "Identifier", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconWeb", { link = "Type", default = true })
  vim.api.nvim_set_hl(0, "CogToolIconTask", { link = "Keyword", default = true })

  -- Tool status icons - use standard diagnostic colors
  vim.api.nvim_set_hl(0, "CogToolStatusPending", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "CogToolStatusSuccess", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "CogToolStatusError", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "CogToolStatusUnknown", { link = "Comment", default = true })

  -- Tool card content - use standard text colors
  vim.api.nvim_set_hl(0, "CogToolCardContent", { link = "Normal", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardMuted", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardLabel", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "CogToolCardValue", { link = "String", default = true })

  -- Tool card sections
  vim.api.nvim_set_hl(0, "CogToolSectionHeader", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CogToolSectionFold", { link = "Folded", default = true })
  vim.api.nvim_set_hl(0, "CogFoldIndicator", { link = "Comment", default = true })

  -- Message content styling
  vim.api.nvim_set_hl(0, "CogUserMessage", { default = true })
  vim.api.nvim_set_hl(0, "CogAssistantMessage", { default = true })
  vim.api.nvim_set_hl(0, "CogSystemMessage", { link = "Comment", default = true })

  -- Message borders - use standard border colors
  vim.api.nvim_set_hl(0, "CogUserBorder", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "CogAssistantBorder", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CogSystemBorder", { link = "DiagnosticWarn", default = true })

  -- Header/Footer - use standard UI colors
  vim.api.nvim_set_hl(0, "CogHeader", { link = "StatusLine", default = true })
  vim.api.nvim_set_hl(0, "CogHeaderTitle", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "CogFooter", { link = "StatusLineNC", default = true })

  -- Status indicators - use standard diagnostic colors
  vim.api.nvim_set_hl(0, "CogStatusOk", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "CogStatusPending", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "CogStatusError", { link = "DiagnosticError", default = true })

  -- Input area - use standard border colors
  vim.api.nvim_set_hl(0, "CogInputBorder", { link = "FloatBorder", default = true })
  vim.api.nvim_set_hl(0, "CogInputPlaceholder", { link = "Comment", default = true })

  -- Separator line
  vim.api.nvim_set_hl(0, "CogSeparator", { link = "FloatBorder", default = true })

  -- Thinking blocks
  vim.api.nvim_set_hl(0, "CogThinkingHeader", { italic = true, link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CogThinkingContent", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CogThinkingBorder", { link = "Comment", default = true })

  -- Diff highlighting in tool cards
  vim.api.nvim_set_hl(0, "CogDiffAdd", { link = "DiffAdd", default = true })
  vim.api.nvim_set_hl(0, "CogDiffDelete", { link = "DiffDelete", default = true })
  vim.api.nvim_set_hl(0, "CogDiffHunk", { link = "DiffChange", default = true })

  -- Token count
  vim.api.nvim_set_hl(0, "CogTokenCount", { link = "Comment", default = true })
end

return M
