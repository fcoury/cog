local M = {}

local tracker = require("cog.buffer.tracker")
local config = require("cog.config")
local ui_diff = require("cog.ui.diff")

local function get_bufnr(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
  end
  return bufnr
end

local function get_buffer_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

local function compute_hunks(old_text, new_text)
  return vim.diff(old_text, new_text, { result_type = "indices" })
end

local function compute_diff_text(path, old_text, new_text)
  local ok, unified = pcall(vim.diff, old_text, new_text, { result_type = "unified", ctxlen = 3 })
  if ok and type(unified) == "string" and unified ~= "" then
    return unified
  end

  local hunks = compute_hunks(old_text, new_text) or {}
  local lines = {}
  if path and path ~= "" then
    table.insert(lines, "--- a/" .. path)
    table.insert(lines, "+++ b/" .. path)
  end
  for _, hunk in ipairs(hunks) do
    local old_start, old_count, new_start, new_count = unpack(hunk)
    table.insert(lines, string.format("@@ -%d,%d +%d,%d @@", old_start, old_count, new_start, new_count))
  end
  return table.concat(lines, "\n")
end

local function apply_hunks(bufnr, new_text, hunks)
  local new_lines = vim.split(new_text, "\n", { plain = true })

  for i = #hunks, 1, -1 do
    local old_start, old_count, new_start, new_count = unpack(hunks[i])
    local hunk_lines = {}
    for j = new_start, new_start + new_count - 1 do
      table.insert(hunk_lines, new_lines[j])
    end

    vim.api.nvim_buf_set_lines(
      bufnr,
      old_start - 1,
      old_start - 1 + old_count,
      false,
      hunk_lines
    )
  end
end

local function apply_hunks_animated(bufnr, new_text, hunks, delay_ms, on_step)
  local new_lines = vim.split(new_text, "\n", { plain = true })
  delay_ms = delay_ms or 50

  for i = #hunks, 1, -1 do
    local hunk = hunks[i]
    local seq = (#hunks - i + 1)
    vim.defer_fn(function()
      local ok, err = pcall(function()
        local old_start, old_count, new_start, new_count = unpack(hunk)
        local hunk_lines = {}
        for j = new_start, new_start + new_count - 1 do
          table.insert(hunk_lines, new_lines[j])
        end

        vim.api.nvim_buf_set_lines(
          bufnr,
          old_start - 1,
          old_start - 1 + old_count,
          false,
          hunk_lines
        )
        if on_step then
          on_step()
        end
      end)
      if not ok then
        vim.notify("Cog: animated apply failed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end, delay_ms * seq)
  end
end

local function has_conflict(path, current_text)
  local last_read = tracker.get_last_read(path)
  if not last_read then
    return false, nil
  end
  if last_read ~= current_text then
    return true, { base = last_read, ours = current_text }
  end
  return false, nil
end

function M.apply(path, new_text, opts)
  if not path or path == "" then
    return false, "missing path"
  end

  local bufnr = get_bufnr(path)
  local current_text = get_buffer_text(bufnr)
  local base_text = current_text
  local conflict, conflict_data = has_conflict(path, current_text)

  local cfg = config.get()
  local auto_apply = cfg.file_operations and cfg.file_operations.auto_apply

  if conflict and not auto_apply then
    ui_diff.show_conflict(path, conflict_data.base, conflict_data.ours, new_text)
    return false, "conflict detected"
  end

  local diff_callback = opts and opts.diff_callback
  if diff_callback then
    diff_callback(compute_diff_text(path, base_text, new_text))
  end

  local hunks = compute_hunks(current_text, new_text)
  if not auto_apply then
    local ok = ui_diff.show_diff(path, current_text, new_text)
    if not ok then
      return false, "diff rejected"
    end
  end

  local animate = cfg.file_operations and cfg.file_operations.animate
  local delay = cfg.file_operations and cfg.file_operations.animate_delay_ms or 50
  if animate then
    apply_hunks_animated(bufnr, new_text, hunks, delay, function()
      if diff_callback then
        diff_callback(compute_diff_text(path, base_text, get_buffer_text(bufnr)))
      end
    end)
  else
    apply_hunks(bufnr, new_text, hunks)
    if diff_callback then
      diff_callback(compute_diff_text(path, base_text, get_buffer_text(bufnr)))
    end
  end

  tracker.record_read(path, new_text)
  return true, nil
end

return M
