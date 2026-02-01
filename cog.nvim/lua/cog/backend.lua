local M = {}

local state = {
  chan = nil,
}

local function ensure_started()
  if state.chan and state.chan > 0 then
    return state.chan
  end

  local config = require("cog.config").get()
  local bin_path = config.backend.bin_path or "cog-agent"

  -- Check if binary exists
  if vim.fn.executable(bin_path) == 0 then
    error("cog-agent not found or not executable: " .. bin_path)
  end

  local chan = vim.fn.jobstart({ bin_path }, { rpc = true })
  if chan <= 0 then
    error("Failed to start cog-agent (jobstart returned: " .. tostring(chan) .. ")")
  end

  state.chan = chan
  return chan
end

function M.start()
  return ensure_started()
end

function M.stop()
  if state.chan and state.chan > 0 then
    vim.fn.jobstop(state.chan)
  end
  state.chan = nil
end

function M.request(method, params)
  ensure_started()
  local ok, result = pcall(vim.rpcrequest, state.chan, method, params or vim.empty_dict())
  if not ok then
    error(result)
  end
  return result
end

function M.notify(method, params)
  ensure_started()
  return vim.rpcnotify(state.chan, method, params or vim.empty_dict())
end

function M._on_notify(event, payload)
  require("cog.session").handle_event(event, payload or {})
end

return M
