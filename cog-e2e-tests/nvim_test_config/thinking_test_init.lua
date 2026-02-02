-- Quick test for thinking block rendering

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

    -- Assistant response with thinking block
    chat.append("assistant", [[<thinking>
Let me analyze the current architecture...

The codebase has three main concerns:
1. Data fetching layer
2. Business logic
3. UI rendering

I should consider:
- Separation of concerns
- Testability
- Performance implications

The best approach would be to extract the business logic into pure functions.
</thinking>

Based on my analysis, I recommend extracting the business logic into a separate module. This will improve testability and make the code easier to maintain.

Here's the plan:
1. Create a new `logic.rs` module
2. Move pure functions there
3. Update the UI to use the new module]])

    -- Another user message
    chat.append("user", "Sounds good, let's do it!")

    vim.defer_fn(function()
      vim.notify("Thinking test loaded", vim.log.levels.INFO)
    end, 100)
  end, 200)
end, 500)
