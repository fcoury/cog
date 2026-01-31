local M = {}

local backend = require("cog.backend")
local config = require("cog.config")
local ui = require("cog.ui")

local state = {
  connected = false,
  session_id = nil,
  agent_info = nil,
}

local function resolve_adapter()
  local opts = config.get()
  local adapter = opts.adapters[opts.adapter]
  if not adapter then
    error("Unknown adapter: " .. tostring(opts.adapter))
  end
  return adapter
end

function M.connect()
  if state.connected then
    return state.agent_info
  end

  local adapter = resolve_adapter()
  local cwd = vim.fn.getcwd()

  local resp = backend.request("cog_connect", {
    command = adapter.command,
    env = adapter.env or {},
    cwd = cwd,
  })

  state.agent_info = resp
  state.connected = true

  local session = backend.request("cog_session_new", { cwd = cwd })
  state.session_id = session.sessionId or session.session_id or session.id

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

  backend.request("cog_prompt", {
    session_id = state.session_id,
    content = text,
  })

  ui.chat.append("user", text)
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
  end

  return vim.inspect(payload)
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
    local text = extract_text_from_update(payload)
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

  if event == "CogError" then
    vim.notify(payload.message or "Unknown error", vim.log.levels.ERROR)
    return
  end
end

return M
