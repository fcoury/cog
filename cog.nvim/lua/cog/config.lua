local M = {}

M.defaults = {
  backend = {
    bin_path = "cog-agent",
    log_level = "info",
    auto_start = true,
  },
  adapter = "codex",
  adapters = {
    codex = {
      command = { "codex-acp" },
      env = {},
    },
    claude_code = {
      command = { "claude-code-acp" },
      env = {},
    },
  },
  ui = {
    chat = {
      position = "right",
      width = "40%",
      border = "rounded",
    },
  },
  permissions = {
    defaults = {
      ["fs.read_text_file"] = "allow_always",
      ["fs.write_text_file"] = "ask",
      ["terminal.create"] = "ask",
      ["_cog.nvim/grep"] = "allow_once",
      ["_cog.nvim/apply_edits"] = "ask",
    },
    timeout_ms = 30000,
    timeout_response = "reject_once",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

function M.get()
  return M.options
end

return M
