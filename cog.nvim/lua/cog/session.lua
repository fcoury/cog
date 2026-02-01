local M = {}

local backend = require("cog.backend")
local config = require("cog.config")
local ui = require("cog.ui")
local vendor = require("cog.vendor")

local state = {
  connected = false,
  session_id = nil,
  agent_info = nil,
  modes = nil,
  models = nil,
}

local function find_codex_binary()
  local opts = config.get()
  local adapter = opts.adapters[opts.adapter]
  if not adapter then
    return nil, "Unknown adapter: " .. tostring(opts.adapter)
  end

  local command = adapter.command or {}
  if #command == 0 then
    return nil, "No command specified for adapter"
  end

  local cmd_name = command[1]

  -- If it's executable as-is, return it
  if vim.fn.executable(cmd_name) == 1 then
    return cmd_name
  end

  -- Only do vendoring for codex-acp
  if cmd_name ~= "codex-acp" and vim.fn.fnamemodify(cmd_name, ":t") ~= "codex-acp" then
    return nil, "Binary not found: " .. cmd_name
  end

  -- Try ~/.local/bin/codex-acp
  local fallback = vim.fn.expand("~/.local/bin/codex-acp")
  if vim.fn.executable(fallback) == 1 then
    return fallback
  end

  -- Try vendored version
  if vendor.is_vendored() then
    return vendor.get_binary_path()
  end

  -- Need to install
  return nil, "not_installed"
end

function M.connect()
  if state.connected then
    return state.agent_info
  end

  local opts = config.get()
  local adapter = opts.adapters[opts.adapter]
  if not adapter then
    error("Unknown adapter: " .. tostring(opts.adapter))
  end

  -- Find the binary (may trigger install)
  local binary_path, err = find_codex_binary()

  if err == "not_installed" then
    -- Install synchronously
    vim.notify("cog.nvim: codex-acp not found. Installing...", vim.log.levels.INFO)
    local ok, install_err = vendor.install_sync()
    if not ok then
      error("Failed to install codex-acp: " .. (install_err or "unknown error"))
    end
    binary_path = vendor.get_binary_path()
  elseif err then
    error(err)
  end

  -- Build the command array
  local cmd = { binary_path }
  if adapter.command and #adapter.command > 1 then
    -- Append any additional args from config
    for i = 2, #adapter.command do
      table.insert(cmd, adapter.command[i])
    end
  end

  local cwd = vim.fn.getcwd()
  local env = adapter.env or {}
  if vim.tbl_isempty(env) then
    env = nil
  end

  local resp = backend.request("cog_connect", {
    command = cmd,
    env = env,
    cwd = cwd,
  })

  state.agent_info = resp
  state.connected = true

  local session = backend.request("cog_session_new", { cwd = cwd })
  state.session_id = session.sessionId or session.session_id or session.id
  state.modes = session.modes
  state.models = session.models

  return state.agent_info
end

function M.disconnect()
  if not state.connected then
    return
  end
  backend.request("cog_disconnect", {})
  state.connected = false
  state.session_id = nil
  state.agent_info = nil
end

function M.prompt(text)
  if not state.connected then
    M.connect()
  end
  if not state.session_id then
    error("No session id")
  end

  ui.chat.append("user", text)
  ui.chat.begin_pending()

  vim.schedule(function()
    local ok, err = pcall(backend.request, "cog_prompt", {
      session_id = state.session_id,
      content = text,
    })
    if not ok then
      ui.chat.clear_pending()
      ui.chat.append("system", "Prompt failed: " .. tostring(err))
    end
  end)
end

function M.cancel()
  if not state.connected or not state.session_id then
    return
  end
  backend.request("cog_cancel", { session_id = state.session_id })
end

function M.set_mode(mode_id)
  if not state.connected or not state.session_id then
    return
  end
  backend.request("cog_set_mode", { session_id = state.session_id, mode_id = mode_id })
end

function M.set_model(model_id)
  if not state.connected or not state.session_id then
    return
  end
  backend.request("cog_set_model", { session_id = state.session_id, model_id = model_id })
end

local function extract_text_from_update(payload)
  if type(payload) ~= "table" then
    return tostring(payload)
  end

  if payload.text then
    return payload.text
  end

  if payload.delta then
    return payload.delta
  end

  if payload.message then
    if type(payload.message) == "table" then
      if payload.message.text then
        return payload.message.text
      end
      if payload.message.content then
        return payload.message.content
      end
    end
  end

  if payload.content then
    if type(payload.content) == "string" then
      return payload.content
    end
    if type(payload.content) == "table" and payload.content.text then
      return payload.content.text
    end
    if type(payload.content) == "table" and payload.content[1] and payload.content[1].text then
      return payload.content[1].text
    end
  end

  return vim.inspect(payload)
end

local function parse_session_update(payload)
  if type(payload) ~= "table" then
    return nil, tostring(payload)
  end

  local update = payload.update or payload
  local update_type = update.type or payload.type
  local text = extract_text_from_update(update)

  return update_type, text, update
end

local function resolve_permission_default(payload)
  local opts = config.get().permissions
  local defaults = opts and opts.defaults or {}

  local method = nil
  if type(payload) == "table" then
    if payload.params and payload.params.toolCall and payload.params.toolCall.method then
      method = payload.params.toolCall.method
    elseif payload.params and payload.params.toolCall and payload.params.toolCall.kind then
      method = payload.params.toolCall.kind
    end
  end

  if method and defaults[method] then
    return defaults[method]
  end

  return nil
end

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

function M.handle_event(event, payload)
  if event == "CogSessionUpdate" then
    local update_type, text, update = parse_session_update(payload)
    if ui.chat.is_pending() then
      ui.chat.clear_pending()
    end
    if update_type == "agentMessageChunk" or update_type == "agentMessage" then
      ui.chat.append_chunk("assistant", text)
      return
    end

    if update_type == "agentThoughtChunk" or update_type == "agentThought" then
      ui.chat.append_chunk("assistant", text)
      return
    end

    if update_type == "toolCall" or update_type == "toolCallUpdate" then
      local status = update.status or (update.toolCall and update.toolCall.status)
      local title = update.title or (update.toolCall and update.toolCall.title) or "Tool"
      if status == "in_progress" then
        ui.progress.start(title)
      elseif status == "completed" or status == "failed" then
        ui.progress.finish(title .. " " .. status)
      end
      local detail = update.content or update.message or update.result
      local line = string.format("[Tool] %s — %s", title, status or "unknown")
      if detail then
        line = line .. ": " .. tostring(detail)
      end
      ui.chat.append("system", line)
      return
    end

    ui.chat.append("assistant", text)
    return
  end

  if event == "CogAcpNotification" then
    ui.chat.append("system", vim.inspect(payload))
    return
  end

  if event == "CogPermissionRequest" then
    local request_id = payload.request_id
    local params = payload.params or {}
    local options = params.options or {}

    local desired = resolve_permission_default(payload)
    if desired and desired ~= "ask" then
      local option_id = select_option_id(options, desired)
      if option_id then
        backend.request("cog_permission_respond", {
          request_id = request_id,
          option_id = option_id,
        })
        return
      end
    end

    ui.permission.request(params, function(option_id)
      if not option_id then
        option_id = select_option_id(options, "reject_once")
      end
      backend.request("cog_permission_respond", {
        request_id = request_id,
        option_id = option_id,
      })
    end)
    return
  end

  if event == "CogFileRead" then
    local request_id = payload.request_id
    local path = payload.path
    local content = require("cog.buffer").read(path)
    backend.request("cog_file_read_response", {
      request_id = request_id,
      content = content,
    })
    return
  end

  if event == "CogFileWrite" then
    local request_id = payload.request_id
    local path = payload.path
    local content = payload.content
    local ok, err = require("cog.buffer").write(path, content)
    backend.request("cog_file_write_response", {
      request_id = request_id,
      success = ok,
      message = err,
    })
    return
  end

  if event == "CogToolRequest" then
    local request_id = payload.request_id
    local method = payload.method
    local params = payload.params or {}

    local ok, result = pcall(function()
      return require("cog.tools").dispatch(method, params)
    end)

    backend.request("cog_tool_response", {
      request_id = request_id,
      ok = ok,
      result = ok and result or nil,
      error = ok and nil or tostring(result),
    })
    return
  end

  if event == "CogError" then
    ui.chat.clear_pending()
    vim.notify(payload.message or "Unknown error", vim.log.levels.ERROR)
    return
  end
end

return M
