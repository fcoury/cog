set nocompatible
set rtp^=$COG_NVIM_TEST_ROOT/cog.nvim
set rtp^=$COG_NVIM_TEST_ROOT/amp.nvim

filetype plugin indent on
syntax on

lua <<'LUA'
local ok, cog = pcall(require, "cog")
if not ok then
  vim.notify("Failed to load cog.nvim: " .. tostring(cog), vim.log.levels.ERROR)
  return
end

cog.setup({
  adapter = "codex-acp",
  adapters = {
    ["codex-acp"] = {
      command = { "codex-acp" },
    },
  },
})

vim.api.nvim_create_user_command("CogSmoke", function()
  require("cog.session").connect()
  vim.notify("Cog connected. Send a prompt to trigger an edit.", vim.log.levels.INFO)
end, {})
LUA

echo "Run :CogSmoke to connect and test edits."
