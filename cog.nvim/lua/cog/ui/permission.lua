local M = {}

local menu_ok, Menu = pcall(require, "nui.menu")
local config = require("cog.config")

local function select_option_id(options, desired_kind)
  if not options then
    return nil
  end

  for _, opt in ipairs(options) do
    if opt.kind == desired_kind or opt.label == desired_kind then
      return opt.optionId
    end
  end

  return nil
end

function M.request(params, callback)
  local options = params.options or {}
  local items = {}
  local done = false
  local timeout_handle = nil

  for _, opt in ipairs(options) do
    table.insert(items, {
      label = opt.label or opt.kind or opt.optionId,
      option_id = opt.optionId,
    })
  end

  if #items == 0 then
    callback(nil)
    return
  end

  local function finish(choice)
    if done then
      return
    end
    done = true
    if timeout_handle then
      timeout_handle:stop()
      timeout_handle:close()
      timeout_handle = nil
    end
    callback(choice)
  end

  local cfg = config.get()
  local timeout_ms = cfg.permissions and cfg.permissions.timeout_ms or 0
  local timeout_response = cfg.permissions and cfg.permissions.timeout_response or "reject_once"

  if timeout_ms > 0 then
    timeout_handle = vim.loop.new_timer()
    timeout_handle:start(timeout_ms, 0, function()
      local option_id = select_option_id(options, timeout_response)
      vim.schedule(function()
        finish(option_id)
      end)
    end)
  end

  if menu_ok then
    local menu_items = {}
    for _, item in ipairs(items) do
      table.insert(menu_items, Menu.item(item.label, { option_id = item.option_id }))
    end

    local menu = Menu({
      position = "50%",
      size = { width = 50, height = math.min(#menu_items + 2, 10) },
      border = { style = "rounded", text = { top = " Permission " } },
    }, {
      lines = menu_items,
      keymap = {
        focus_next = { "j", "<Down>" },
        focus_prev = { "k", "<Up>" },
        submit = { "<CR>" },
      },
      on_submit = function(item)
        finish(item.option_id)
        menu:unmount()
      end,
    })

    menu:mount()
    return
  end

  vim.ui.select(items, {
    prompt = params.title or "Permission required",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      finish(choice.option_id)
    else
      finish(nil)
    end
  end)
end

return M
