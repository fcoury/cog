-- Test for thinking block STREAMING (like real Claude output)

local project_root = "/Volumes/External/code-external/cog"
local cog_nvim_path = project_root .. "/cog.nvim"

vim.opt.runtimepath:prepend(cog_nvim_path)
vim.opt.swapfile = false

require("cog").setup({
  backend = { auto_start = false },
  ui = {
    chat = {
      layout = "vsplit",
      width = "50%",
      show_borders = false,
    },
    tool_calls = { style = "card", icons = true },
  },
})

vim.defer_fn(function()
  local chat = require("cog.ui.chat")
  chat.open()

  vim.defer_fn(function()
    -- User question
    chat.append("user", "What's the best approach for this refactor?")

    -- Start assistant stream
    chat.begin_stream("assistant")

    -- Simulate streaming thinking content (like real Claude)
    local thinking_chunks = {
      { text = "Let me analyze ", kind = "thought" },
      { text = "the current architecture...\n\n", kind = "thought" },
      { text = "The codebase has three main concerns:\n", kind = "thought" },
      { text = "1. Data fetching layer\n", kind = "thought" },
      { text = "2. Business logic\n", kind = "thought" },
      { text = "3. UI rendering\n\n", kind = "thought" },
      { text = "I should consider:\n", kind = "thought" },
      { text = "- Separation of concerns\n", kind = "thought" },
      { text = "- Testability\n", kind = "thought" },
    }

    -- Stream thinking chunks with delays
    local i = 1
    local function stream_next()
      if i <= #thinking_chunks then
        local chunk = thinking_chunks[i]
        chat.append_stream_chunk("assistant", chunk.text, chunk.kind)
        i = i + 1
        vim.defer_fn(stream_next, 50)
      else
        -- Now stream regular content (end thinking)
        chat.append_stream_chunk("assistant", "Based on my analysis, ", "message")
        vim.defer_fn(function()
          chat.append_stream_chunk("assistant", "I recommend extracting the business logic.\n\n", "message")
          chat.append_stream_chunk("assistant", "Here's the plan:\n", "message")
          chat.append_stream_chunk("assistant", "1. Create a new module\n", "message")
          chat.append_stream_chunk("assistant", "2. Move pure functions there", "message")
          chat.end_stream()
          vim.notify("Streaming test loaded", vim.log.levels.INFO)
        end, 100)
      end
    end

    stream_next()
  end, 200)
end, 500)
