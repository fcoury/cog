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

  local chan = vim.fn.jobstart({ bin_path }, { rpc = true })
  if chan <= 0 then
    error("Failed to start cog-agent")
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
  return vim.rpcrequest(state.chan, method, params or vim.empty_dict())
end

function M.notify(method, params)
  ensure_started()
  return vim.rpcnotify(state.chan, method, params or vim.empty_dict())
end

function M._on_notify(event, payload)
  require("cog.session").handle_event(event, payload or {})
end

return M
