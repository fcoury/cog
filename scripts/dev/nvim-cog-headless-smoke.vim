set nocompatible
set rtp^=$COG_NVIM_TEST_ROOT/cog.nvim
set rtp^=$COG_NVIM_TEST_ROOT/amp.nvim

filetype plugin indent on
syntax on

lua << LUA
local ui = require("cog.ui")
local session = require("cog.session")

ui.chat.open()

-- Simulate streaming assistant output
session.handle_event("CogSessionUpdate", {
  sessionUpdate = "agent_message_chunk",
  text = "Hello",
})
session.handle_event("CogSessionUpdate", {
  sessionUpdate = "agent_message_chunk",
  text = " world",
})
session.handle_event("CogSessionUpdate", {
  sessionUpdate = "agent_message",
  text = "!",
})

-- Simulate an edit tool call with diff updates
local tool_call_id = "test_tool_1"
session.handle_event("CogSessionUpdate", {
  sessionUpdate = "tool_call",
  toolCall = {
    toolCallId = tool_call_id,
    kind = "edit",
    title = "Edit README.md",
    status = "in_progress",
    locations = { { path = "README.md" } },
  },
})

session.handle_event("CogSessionUpdate", {
  sessionUpdate = "tool_call_update",
  toolCall = {
    toolCallId = tool_call_id,
    kind = "edit",
    title = "Edit README.md",
    status = "in_progress",
    locations = { { path = "README.md" } },
    diffText = "--- a/README.md\n+++ b/README.md\n@@ -1,1 +1,1 @@\n-Hello\n+Hello world",
  },
})

session.handle_event("CogSessionUpdate", {
  sessionUpdate = "tool_call_update",
  toolCall = {
    toolCallId = tool_call_id,
    kind = "edit",
    title = "Edit README.md",
    status = "completed",
    locations = { { path = "README.md" } },
    diffText = "--- a/README.md\n+++ b/README.md\n@@ -1,1 +1,1 @@\n-Hello\n+Hello world",
  },
})

local bufnr = ui.chat._get_message_buf()
local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
local text = table.concat(lines, "\n")

local function assert_contains(needle)
  if not text:find(needle, 1, true) then
    vim.api.nvim_err_writeln("Smoke test missing: " .. needle)
    vim.cmd("cquit 1")
  end
end

assert_contains("Hello")
assert_contains("world")
assert_contains("Diff:")
assert_contains("--- a/README.md")
assert_contains("+Hello world")

local out_dir = vim.fn.fnamemodify(vim.env.COG_NVIM_TEST_ROOT .. "/scripts/dev/out", ":p")
vim.fn.mkdir(out_dir, "p")
vim.fn.writefile(lines, out_dir .. "/chat.txt")
vim.cmd("quitall!")
LUA
