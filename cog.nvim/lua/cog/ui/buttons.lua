-- Inline button group component for chat UI
local M = {}

local config = require("cog.config")

-- Namespace for button rendering
local ns = vim.api.nvim_create_namespace("cog_inline_buttons")

-- Active button group state
local active_group = nil

-- Create a new button group
-- options: array of { id = string, label = string }
-- callback: function(selected_id) called when a button is selected
function M.create(bufnr, line, options, callback)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  -- Clear any existing button group
  M.clear()

  local group = {
    bufnr = bufnr,
    line = line,
    options = options,
    callback = callback,
    focus_index = 1,
    keymaps = {},
  }

  active_group = group

  -- Render the buttons
  M.render(group)

  -- Setup keymaps
  M.setup_keymaps(group)

  return group
end

-- Render the button group at the specified line
function M.render(group)
  if not group or not vim.api.nvim_buf_is_valid(group.bufnr) then
    return
  end

  -- Clear previous extmarks on this line
  vim.api.nvim_buf_clear_namespace(group.bufnr, ns, group.line, group.line + 1)

  -- Build button text with highlighting
  local virt_text = {}
  for i, opt in ipairs(group.options) do
    -- Separator between buttons
    if i > 1 then
      table.insert(virt_text, { "  ", "Normal" })
    end

    -- Button styling: focused vs unfocused
    local is_focused = i == group.focus_index
    local bracket_hl = is_focused and "CogButtonFocused" or "CogButton"
    local label_hl = is_focused and "CogButtonLabelFocused" or "CogButtonLabel"

    table.insert(virt_text, { "[", bracket_hl })
    table.insert(virt_text, { opt.label, label_hl })
    table.insert(virt_text, { "]", bracket_hl })
  end

  -- Add navigation hint
  table.insert(virt_text, { "  (Tab/Shift-Tab to navigate, Enter to confirm)", "Comment" })

  -- Set extmark with virtual text
  pcall(vim.api.nvim_buf_set_extmark, group.bufnr, ns, group.line, 0, {
    virt_text = virt_text,
    virt_text_pos = "eol",
    priority = 200,
  })
end

-- Setup keymaps for the button group
function M.setup_keymaps(group)
  if not group or not vim.api.nvim_buf_is_valid(group.bufnr) then
    return
  end

  -- Tab - move to next button
  local tab_map = vim.keymap.set("n", "<Tab>", function()
    if active_group and active_group == group then
      group.focus_index = (group.focus_index % #group.options) + 1
      M.render(group)
    end
  end, { buffer = group.bufnr, silent = true })
  table.insert(group.keymaps, { mode = "n", lhs = "<Tab>" })

  -- Shift-Tab - move to previous button
  vim.keymap.set("n", "<S-Tab>", function()
    if active_group and active_group == group then
      group.focus_index = group.focus_index - 1
      if group.focus_index < 1 then
        group.focus_index = #group.options
      end
      M.render(group)
    end
  end, { buffer = group.bufnr, silent = true })
  table.insert(group.keymaps, { mode = "n", lhs = "<S-Tab>" })

  -- Enter - select current button
  vim.keymap.set("n", "<CR>", function()
    if active_group and active_group == group then
      local selected = group.options[group.focus_index]
      if selected and group.callback then
        M.clear()
        group.callback(selected.id)
      end
    end
  end, { buffer = group.bufnr, silent = true })
  table.insert(group.keymaps, { mode = "n", lhs = "<CR>" })

  -- Number keys for quick selection
  for i, opt in ipairs(group.options) do
    if i <= 9 then
      vim.keymap.set("n", tostring(i), function()
        if active_group and active_group == group then
          if group.callback then
            M.clear()
            group.callback(opt.id)
          end
        end
      end, { buffer = group.bufnr, silent = true })
      table.insert(group.keymaps, { mode = "n", lhs = tostring(i) })
    end
  end

  -- Escape - cancel/reject
  vim.keymap.set("n", "<Esc>", function()
    if active_group and active_group == group then
      M.clear()
      if group.callback then
        group.callback(nil) -- nil indicates cancellation
      end
    end
  end, { buffer = group.bufnr, silent = true })
  table.insert(group.keymaps, { mode = "n", lhs = "<Esc>" })
end

-- Clear the active button group
function M.clear()
  if not active_group then
    return
  end

  local group = active_group

  -- Clear extmarks
  if group.bufnr and vim.api.nvim_buf_is_valid(group.bufnr) then
    vim.api.nvim_buf_clear_namespace(group.bufnr, ns, group.line, group.line + 1)

    -- Remove keymaps
    for _, map in ipairs(group.keymaps or {}) do
      pcall(vim.keymap.del, map.mode, map.lhs, { buffer = group.bufnr })
    end
  end

  active_group = nil
end

-- Check if a button group is currently active
function M.is_active()
  return active_group ~= nil
end

-- Get the active group
function M.get_active()
  return active_group
end

return M
