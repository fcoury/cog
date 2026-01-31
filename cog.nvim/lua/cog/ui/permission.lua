local M = {}

function M.request(params, callback)
  local options = params.options or {}
  local items = {}

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

  vim.ui.select(items, {
    prompt = params.title or "Permission required",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      callback(choice.option_id)
    else
      callback(nil)
    end
  end)
end

return M
