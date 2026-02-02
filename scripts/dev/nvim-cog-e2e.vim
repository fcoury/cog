set nocompatible
set rtp^=$COG_NVIM_TEST_ROOT/cog.nvim
set rtp^=$COG_NVIM_TEST_ROOT/amp.nvim

filetype plugin indent on
syntax on

lua << LUA
local cog = require("cog")
local session = require("cog.session")
local ui = require("cog.ui")

local prompt = vim.env.COG_E2E_PROMPT
local workdir = vim.env.COG_E2E_WORKDIR
local marker = vim.env.COG_E2E_MARKER or "COG_E2E_MARKER"
local base_text = "E2E base"
local cwd = vim.fn.getcwd()

if not prompt or prompt == "" then
  vim.notify("COG_E2E_PROMPT not set; skipping e2e", vim.log.levels.WARN)
  vim.cmd("quitall!")
  return
end

if workdir and workdir ~= "" then
  vim.cmd("cd " .. vim.fn.fnameescape(workdir))
  cwd = vim.fn.getcwd()
end

local agent_bin = vim.env.COG_NVIM_AGENT_BIN or "cog-agent"
cog.setup({
  adapter = "codex-acp",
  adapters = {
    ["codex-acp"] = {
      command = { "codex-acp" },
    },
  },
  backend = {
    bin_path = agent_bin,
  },
  file_operations = {
    auto_apply = true,
  },
  permissions = {
    auto_approve = true,
    defaults = {
      ["fs.read_text_file"] = "allow_once",
      ["fs.write_text_file"] = "allow_once",
      ["read"] = "allow_once",
      ["list"] = "allow_once",
      ["list_directory"] = "allow_once",
      ["search"] = "allow_once",
      ["write"] = "allow_once",
      ["edit"] = "allow_once",
    },
  },
})

ui.chat.open()
session.connect()
session.prompt(prompt)

local bufnr = ui.chat._get_message_buf()
local function get_text()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

local ok = vim.wait(60000, function()
  local text = get_text()
  if text:find("Prompt failed", 1, true) then
    return true
  end
  if text:find("completed", 1, true) then
    return true
  end
  if text:find("Diff:", 1, true) then
    return true
  end
  return false
end, 200)

local out_dir = vim.fn.fnamemodify(vim.env.COG_NVIM_TEST_ROOT .. "/scripts/dev/out", ":p")
vim.fn.mkdir(out_dir, "p")
local text = get_text()
vim.fn.writefile(vim.split(text, "\n", { plain = true }), out_dir .. "/chat-e2e.txt")

-- Verify target file contents if possible
local target = vim.env.COG_E2E_TARGET or "README.md"
local target_path = cwd .. "/" .. target
local file_ok, file_lines = pcall(vim.fn.readfile, target_path)
if not file_ok then
  local alt_path = vim.fn.fnamemodify(target_path, ":p")
  file_ok, file_lines = pcall(vim.fn.readfile, alt_path)
  if not file_ok then
    local bufnr = vim.fn.bufnr(target_path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      file_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      file_ok = true
    else
      vim.api.nvim_err_writeln("E2E failed: could not read target file " .. target_path)
      vim.cmd("cquit 1")
    end
  end
end
local file_text = table.concat(file_lines, "\n")
if not file_text:find(marker, 1, true) then
  if file_text == base_text then
    vim.api.nvim_err_writeln("E2E failed: target file unchanged and marker missing")
    vim.cmd("cquit 1")
  else
    vim.notify("E2E warning: marker missing, but file changed", vim.log.levels.WARN)
  end
end

if not ok then
  vim.api.nvim_err_writeln("E2E timeout: no diff or failure detected")
  vim.cmd("cquit 1")
else
  if text:find("Prompt failed", 1, true) then
    vim.api.nvim_err_writeln("E2E failed: prompt failure detected")
    vim.cmd("cquit 1")
  end
end

vim.cmd("quitall!")
LUA
