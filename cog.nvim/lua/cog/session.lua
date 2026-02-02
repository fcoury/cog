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
  tool_call_cache = {},
  active_edit_tool_calls = {},
}

local function normalize_path(path)
  if not path or path == "" then
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
end

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
  -- Try to cleanly disconnect from ACP
  pcall(backend.request, "cog_disconnect", {})
  -- Stop the backend process
  backend.stop()
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
    local ok, result = pcall(backend.request, "cog_prompt", {
      session_id = state.session_id,
      content = text,
    })
    if not ok then
      -- If it's a timeout, try reconnecting and retrying once
      local err_str = tostring(result)
      if err_str:match("timed out") then
        vim.notify("cog.nvim: First prompt timed out, reconnecting...", vim.log.levels.WARN)
        -- Try to reconnect
        state.connected = false
        local reconnect_ok = pcall(M.connect)
        if reconnect_ok and state.session_id then
          -- Retry the prompt
          local retry_ok, retry_result = pcall(backend.request, "cog_prompt", {
            session_id = state.session_id,
            content = text,
          })
          if retry_ok then
            ui.chat.end_stream("assistant")
            return
          end
          result = retry_result
        end
      end
      ui.chat.clear_pending()
      ui.chat.append("system", "Prompt failed: " .. tostring(result))
      ui.chat.end_stream("assistant")
      return
    end
    ui.chat.end_stream("assistant")
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

local function extract_text_from_content(content)
  if type(content) == "string" then
    return content
  end
  if type(content) ~= "table" then
    return nil
  end
  if content.text then
    return content.text
  end
  if content.content and type(content.content) == "table" and content.content.text then
    return content.content.text
  end
  if content[1] ~= nil then
    local parts = {}
    for _, item in ipairs(content) do
      if type(item) == "string" then
        table.insert(parts, item)
      elseif type(item) == "table" then
        if item.text then
          table.insert(parts, item.text)
        elseif item.content and type(item.content) == "table" and item.content.text then
          table.insert(parts, item.content.text)
        end
      end
    end
    if #parts > 0 then
      return table.concat(parts, "")
    end
  end
  return nil
end

local function extract_text_from_update(payload)
  if type(payload) ~= "table" then
    return tostring(payload)
  end

  if payload.text then
    return payload.text
  end

  if payload.delta then
    if type(payload.delta) == "string" then
      return payload.delta
    end
    if type(payload.delta) == "table" then
      if payload.delta.text then
        return payload.delta.text
      end
      local delta_content = extract_text_from_content(payload.delta.content)
      if delta_content then
        return delta_content
      end
    end
  end

  if payload.message then
    if type(payload.message) == "table" then
      if payload.message.text then
        return payload.message.text
      end
      local message_content = extract_text_from_content(payload.message.content)
      if message_content then
        return message_content
      end
    end
  end

  if payload.content then
    local content_text = extract_text_from_content(payload.content)
    if content_text then
      return content_text
    end
  end

  return vim.inspect(payload)
end

local function normalize_update_type(update_type)
  if not update_type then
    return nil
  end
  if type(update_type) ~= "string" then
    return tostring(update_type)
  end
  local normalized = update_type
    :gsub("([a-z0-9])([A-Z])", "%1_%2")
    :gsub("%-", "_")
    :gsub("%s+", "_")
    :lower()
  return normalized
end

local function is_list(value)
  if type(vim.islist) == "function" then
    return vim.islist(value)
  end
  return vim.tbl_islist(value)
end

-- Extract readable text from a value, handling common structures
local function extract_display_text(value, max_len)
  if value == nil then
    return nil
  end
  max_len = max_len or 500

  if type(value) == "string" then
    if #value > max_len then
      return value:sub(1, max_len) .. "..."
    end
    return value
  end

  if type(value) ~= "table" then
    return tostring(value)
  end

  -- Handle common output structures
  -- rawOutput often has aggregated_output with the actual content
  if value.aggregated_output then
    local text = tostring(value.aggregated_output)
    if #text > max_len then
      return text:sub(1, max_len) .. "..."
    end
    return text
  end

  -- Handle output with text field
  if value.text then
    return tostring(value.text)
  end

  -- Handle output with content field
  if value.content then
    if type(value.content) == "string" then
      return value.content
    elseif type(value.content) == "table" and value.content.text then
      return value.content.text
    end
  end

  -- For locations, extract just the paths
  if value[1] and value[1].path then
    local paths = {}
    for _, loc in ipairs(value) do
      if loc.path then
        table.insert(paths, loc.path)
      end
    end
    return table.concat(paths, "\n")
  end

  -- For input with command, show the command
  if value.command then
    if type(value.command) == "table" then
      return table.concat(value.command, " ")
    end
    return tostring(value.command)
  end

  -- Fallback to compact inspect
  local text = vim.inspect(value, { indent = "  ", newline = " " })
  if #text > max_len then
    return text:sub(1, max_len) .. "..."
  end
  return text
end

local function format_tool_call_detail(tool_call, update)
  local sections = {}

  local kind = (tool_call and tool_call.kind) or update.kind
  local tool_name = (tool_call and tool_call.tool_name) or (tool_call and tool_call.toolName) or update.tool_name
  local locations = (tool_call and (tool_call.locations or tool_call.location)) or update.locations
  local raw_input = (tool_call and (tool_call.rawInput or tool_call.raw_input)) or update.rawInput or update.raw_input
  local raw_output = (tool_call and (tool_call.rawOutput or tool_call.raw_output)) or update.rawOutput or update.raw_output

  if kind then
    table.insert(sections, "Kind: " .. tostring(kind))
  end
  if tool_name then
    table.insert(sections, "Name: " .. tostring(tool_name))
  end

  -- Format locations as simple paths
  if locations then
    local loc_text = extract_display_text(locations)
    if loc_text then
      table.insert(sections, "Locations: " .. loc_text)
    end
  end

  -- Format input - show command or simplified view
  if raw_input then
    local input_text = extract_display_text(raw_input, 200)
    if input_text then
      table.insert(sections, "Input: " .. input_text)
    end
  end

  -- Format output - extract actual content
  if raw_output then
    local output_text = extract_display_text(raw_output, 300)
    if output_text then
      table.insert(sections, "Output: " .. output_text)
    end
  end

  return table.concat(sections, "\n")
end

local function log_session_update(payload, update_type, text)
  local debug = config.get().debug or {}
  if not debug.session_updates then
    return
  end

  local path = debug.session_updates_path or (vim.fn.stdpath("cache") .. "/cog-session-updates.log")
  local ok, fh = pcall(io.open, path, "a")
  if not ok or not fh then
    return
  end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  fh:write(string.format("[%s] type=%s text=%s\n", timestamp, tostring(update_type), tostring(text)))
  fh:write(vim.inspect(payload))
  fh:write("\n---\n")
  fh:close()
end

local function parse_session_update(payload)
  if type(payload) ~= "table" then
    return nil, tostring(payload)
  end

  -- Only use nested update/sessionUpdate if they're tables, not type strings
  local update
  if type(payload.update) == "table" then
    update = payload.update
  elseif type(payload.sessionUpdate) == "table" then
    update = payload.sessionUpdate
  elseif type(payload.session_update) == "table" then
    update = payload.session_update
  else
    update = payload
  end

  -- Check for explicit type indicator strings at ALL levels
  -- The sessionUpdate field can be at payload level OR inside the nested update
  local update_type

  -- Check inside the nested update object first (most common case from logs)
  if type(update.sessionUpdate) == "string" then
    update_type = update.sessionUpdate
  elseif type(update.session_update) == "string" then
    update_type = update.session_update
  -- Then check at payload level
  elseif type(payload.sessionUpdate) == "string" then
    update_type = payload.sessionUpdate
  elseif type(payload.session_update) == "string" then
    update_type = payload.session_update
  elseif type(payload.update) == "string" then
    update_type = payload.update
  end

  -- Fall back to nested type fields if no explicit indicator
  if not update_type then
    update_type = update.type
      or update.update_type
      or update.updateType
      or update.event
      or payload.type
  end

  -- NOTE: Don't use update.kind or payload.kind as update_type
  -- because "kind" refers to the tool kind (read/write/bash), not the message type

  local normalized_type = normalize_update_type(update_type)
  local text = extract_text_from_update(update)

  return normalized_type, text, update
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

function M.update_tool_call_diff(tool_call_id, diff_text)
  if not tool_call_id or not diff_text then
    return
  end

  local cached = state.tool_call_cache[tool_call_id] or {}
  local merged = vim.tbl_extend("force", {}, cached, { diff = diff_text })
  if not merged.title then
    merged.title = "Edit"
  end
  if not merged.kind then
    merged.kind = "edit"
  end
  if not merged.status then
    merged.status = "in_progress"
  end

  ui.chat.upsert_tool_call(tool_call_id, merged)
  state.tool_call_cache[tool_call_id] = merged
end

function M.handle_event(event, payload)
  if event == "CogSessionUpdate" then
    if type(payload) == "table" and is_list(payload) then
      for _, item in ipairs(payload) do
        M.handle_event("CogSessionUpdate", item)
      end
      return
    end

    local update_type, text, update = parse_session_update(payload)
    log_session_update(payload, update_type, text)

    -- DEBUG: Uncomment to see what update_type is detected
    -- vim.notify("update_type: " .. tostring(update_type), vim.log.levels.INFO)

    if ui.chat.is_pending() then
      ui.chat.clear_pending()
    end
    if update_type == "agent_message_chunk" then
      ui.chat.append_stream_chunk("assistant", text, "message")
      return
    end

    if update_type == "agent_message" then
      ui.chat.append_stream_chunk("assistant", text, "message")
      -- Extract token count if available
      local tokens = update.usage and (update.usage.output_tokens or update.usage.outputTokens)
        or update.outputTokens or update.output_tokens
        or (payload.usage and (payload.usage.output_tokens or payload.usage.outputTokens))
      ui.chat.end_stream(tokens)
      return
    end

    if update_type == "agent_thought_chunk" then
      ui.chat.append_stream_chunk("assistant", text, "thought")
      return
    end

    if update_type == "agent_thought" then
      ui.chat.append_stream_chunk("assistant", text, "thought")
      ui.chat.end_stream("assistant")
      return
    end

    if update_type == "tool_call" or update_type == "tool_call_update" then
      ui.chat.end_stream("assistant")
      local tool_call = update.toolCall or update.tool_call or payload.toolCall or payload.tool_call or update
      local status = update.status or (tool_call and tool_call.status) or payload.status
      local title = update.title or (tool_call and tool_call.title) or payload.title or "Tool"
      if status == "in_progress" then
        ui.progress.start(title)
      elseif status == "completed" or status == "failed" then
        ui.progress.finish(title .. " " .. status)
      end

      -- Extract tool kind for status indicator
      local kind_for_status = (tool_call and tool_call.kind) or update.kind or payload.kind
      if type(kind_for_status) == "string" then
        kind_for_status = kind_for_status:sub(1, 1):upper() .. kind_for_status:sub(2):lower()
      end

      -- Update status indicator with tool information
      local status_opts = {
        tool_name = kind_for_status or title,
        tool_kind = (tool_call and tool_call.kind) or update.kind or payload.kind,
      }
      -- Extract command for bash tools
      local raw_input_for_status = (tool_call and (tool_call.rawInput or tool_call.raw_input))
        or update.rawInput or update.raw_input
      if raw_input_for_status and raw_input_for_status.command then
        if type(raw_input_for_status.command) == "table" then
          status_opts.command = raw_input_for_status.command[#raw_input_for_status.command]
        else
          status_opts.command = tostring(raw_input_for_status.command)
        end
      end
      ui.chat.set_tool_status(status or "in_progress", status_opts)
      local tool_call_id = (tool_call and (tool_call.toolCallId or tool_call.tool_call_id or tool_call.id))
        or update.toolCallId
        or update.tool_call_id
        or payload.toolCallId
        or payload.tool_call_id

      -- Extract tool kind for icon
      local kind = (tool_call and tool_call.kind) or update.kind or payload.kind
      if type(kind) == "string" then
        kind = kind:lower()
      end

      -- Build structured tool data for cleaner display
      local tool_data = {
        kind = kind,
        title = title,
        status = status,
      }

      -- Extract command from rawInput
      local raw_input = (tool_call and (tool_call.rawInput or tool_call.raw_input))
        or update.rawInput or update.raw_input
      if raw_input then
        if raw_input.command then
          if type(raw_input.command) == "table" then
            -- Get the actual command (last element usually has the command)
            local cmd = raw_input.command[#raw_input.command]
            tool_data.command = cmd
          else
            tool_data.command = tostring(raw_input.command)
          end
        end
        if raw_input.cwd then
          tool_data.cwd = raw_input.cwd
        end
      end

      -- Extract output from rawOutput
      local raw_output = (tool_call and (tool_call.rawOutput or tool_call.raw_output))
        or update.rawOutput or update.raw_output
      if raw_output then
        -- Prefer stdout, then aggregated_output, then formatted_output
        tool_data.output = raw_output.stdout
          or raw_output.aggregated_output
          or raw_output.formatted_output
        tool_data.exit_code = raw_output.exit_code
      end

      -- Extract diff text (if provided)
      local diff_text = (tool_call and (tool_call.diffText or tool_call.diff_text))
        or update.diffText or update.diff_text
        or payload.diffText or payload.diff_text
      if diff_text then
        tool_data.diff = diff_text
      end

      -- Extract locations
      local locations = (tool_call and (tool_call.locations or tool_call.location))
        or update.locations or update.location
      if locations and type(locations) == "table" then
        local paths = {}
        for _, loc in ipairs(locations) do
          if loc.path then
            table.insert(paths, loc.path)
          end
        end
        if #paths > 0 then
          tool_data.locations = paths
        end
      end

      ui.chat.upsert_tool_call(tool_call_id, tool_data)

      -- Cache latest tool data for diff updates
      if tool_call_id then
        local cached = state.tool_call_cache[tool_call_id] or {}
        for key, value in pairs(tool_data) do
          if value ~= nil then
            cached[key] = value
          end
        end
        state.tool_call_cache[tool_call_id] = cached

        -- Track active edit tool calls by path for write mapping
        if cached.kind == "edit" and cached.locations then
          for _, loc in ipairs(cached.locations) do
            local normalized = normalize_path(loc)
            if normalized then
              if cached.status == "completed" or cached.status == "failed" then
                if state.active_edit_tool_calls[normalized] == tool_call_id then
                  state.active_edit_tool_calls[normalized] = nil
                end
              else
                state.active_edit_tool_calls[normalized] = tool_call_id
              end
            end
          end
        end
      end
      return
    end

    if update_type == "plan"
      or update_type == "available_commands_update"
      or update_type == "current_mode_update"
      or update_type == "config_option_update"
    then
      ui.chat.end_stream()
      ui.chat.append("system", text)
      return
    end

    -- Handle usage/token updates
    if update_type == "usage" or update_type == "usage_update" then
      local usage = update.usage or payload.usage or update
      local total_tokens = usage.total_tokens or usage.totalTokens
        or ((usage.input_tokens or usage.inputTokens or 0) + (usage.output_tokens or usage.outputTokens or 0))
      if total_tokens and total_tokens > 0 then
        require("cog.ui.split").set_session_info({ tokens = total_tokens })
      end
      return
    end

    if text and text ~= "" then
      ui.chat.append_stream_chunk("assistant", text, "message")
      return
    end

    ui.chat.append("assistant", tostring(text))
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

    local perm_opts = config.get().permissions or {}
    if perm_opts.auto_approve then
      local option_id = select_option_id(options, "allow_once")
        or select_option_id(options, "allow_always")
        or select_option_id(options, "approved")
      if option_id then
        backend.request("cog_permission_respond", {
          request_id = request_id,
          option_id = option_id,
        })
        return
      end
    end

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
    local normalized = normalize_path(path)
    local tool_call_id = normalized and state.active_edit_tool_calls[normalized] or nil
    local ok, err = require("cog.buffer").write(path, content, {
      diff_callback = function(diff_text)
        if tool_call_id then
          M.update_tool_call_diff(tool_call_id, diff_text)
        end
      end,
    })
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
