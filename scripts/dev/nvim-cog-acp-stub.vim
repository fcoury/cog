set nocompatible
set rtp^=$COG_NVIM_TEST_ROOT/cog.nvim
set rtp^=$COG_NVIM_TEST_ROOT/amp.nvim

filetype plugin indent on
syntax on

lua << LUA
local cog = require("cog")
local session = require("cog.session")
local ui = require("cog.ui")

local workdir = vim.env.COG_ACP_STUB_WORKDIR
local target = vim.env.COG_ACP_STUB_TARGET
local content = vim.env.COG_ACP_STUB_CONTENT or "Stub wrote content"
local agent_bin = vim.env.COG_NVIM_AGENT_BIN or "cog-agent"
local stub_bin = vim.env.COG_ACP_STUB_BIN or "acp_stub"

if workdir and workdir ~= "" then
  vim.cmd("cd " .. vim.fn.fnameescape(workdir))
end

cog.setup({
  adapter = "acp_stub",
  adapters = {
    acp_stub = {
      command = { stub_bin },
      env = {
        ACP_STUB_TARGET_PATH = target,
        ACP_STUB_WRITE_CONTENT = content,
      },
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
session.prompt("Use the stub to write the file and report success.")

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
vim.fn.writefile(vim.split(text, "\n", { plain = true }), out_dir .. "/chat-acp-stub.txt")

if not ok then
  vim.api.nvim_err_writeln("ACP stub test timeout: no diff or completion detected")
  vim.cmd("cquit 1")
end

if target and target ~= "" then
  local function read_target_text()
    local bufnr = vim.fn.bufnr(target)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end
    local file_ok, file_lines = pcall(vim.fn.readfile, target)
    if file_ok and file_lines then
      return table.concat(file_lines, "\n")
    end
    return nil
  end

  local applied = vim.wait(10000, function()
    local text = read_target_text()
    return text and text:find(content, 1, true) ~= nil
  end, 100)

  if not applied then
    local final_text = read_target_text()
    if not final_text then
      vim.api.nvim_err_writeln("ACP stub test failed: could not read target file " .. target)
      vim.cmd("cquit 1")
    else
      vim.api.nvim_err_writeln("ACP stub test failed: target content mismatch")
      vim.cmd("cquit 1")
    end
  end
end

local function assert_contains(needle)
  if not text:find(needle, 1, true) then
    vim.api.nvim_err_writeln("ACP stub test missing: " .. needle)
    vim.cmd("cquit 1")
  end
end

assert_contains("Stub: ")
assert_contains("streaming response.")
assert_contains("┌─  Edit")
assert_contains("Diff:")

vim.cmd("quitall!")
LUA
