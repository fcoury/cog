local M = {}

M.defaults = {
	backend = {
		bin_path = "cog-agent",
		log_level = "info",
		auto_start = true,
	},
	adapter = "codex",
	adapters = {
		codex = {
			command = { "codex-acp" },
			env = {},
		},
		claude_code = {
			command = { "claude-code-acp" },
			env = {},
		},
	},
	ui = {
		chat = {
			-- Layout type: "popup" (floating), "vsplit" (vertical split sidebar), "hsplit" (horizontal split panel)
			layout = "vsplit",
			position = "right",
			width = "40%",
			border = "rounded",
			input_height = 5,
			input_submit = "<C-CR>",
			input_send_on_enter = true,
			auto_open = false,
			pending_message = "Thinking...",
			pending_timeout_ms = 15000,
			pending_timeout_message = "No response yet; still waiting...",
			disable_input_while_waiting = true,
			stream_idle_timeout_ms = 300,

			-- Visual options (OpenCode-inspired)
			show_borders = false, -- Show left border on messages (disabled by default for cleaner look)
			show_header = true, -- Show header with session info (winbar)
			show_footer = true, -- Show footer with status in statusline
			show_input_placeholder = true, -- Show placeholder text in empty input
			message_padding = 1, -- Lines between messages

			-- Icons for message headers
			user_icon = "●", -- Icon for user messages
			assistant_icon = "◆", -- Icon for assistant messages
		},
		progress = {
			provider = "fidget",
		},
		tool_calls = {
			-- Visual style: "card" (bordered cards), "minimal" (simple display), "inline" (compact)
			style = "card",
			-- Show tool-specific icons (requires Nerd Font)
			icons = true,
			-- Show animated spinner for in-progress tools
			animate_spinner = true,
			-- Maximum lines to show in content preview before truncating
			max_preview_lines = 8,
			-- Show input section in tool cards
			show_input = true,
			-- Show output section in tool cards
			show_output = true,
			-- Border characters for card style
			border = {
				-- Normal state (solid)
				normal = {
					top_left = "┌",
					top = "─",
					top_right = "┐",
					left = "│",
					right = "│",
					bottom_left = "└",
					bottom = "─",
					bottom_right = "┘",
					header_left = "├",
					header_right = "┤",
				},
				-- Error/failed state (dashed - inspired by Zed)
				error = {
					top_left = "┌",
					top = "╌",
					top_right = "┐",
					left = "╎",
					right = "╎",
					bottom_left = "└",
					bottom = "╌",
					bottom_right = "┘",
					header_left = "├",
					header_right = "┤",
				},
			},
		},
	},
	file_operations = {
		auto_apply = false,
		auto_save = false,
		animate = true,
		animate_delay_ms = 50,
	},
	permissions = {
		defaults = {
			["fs.read_text_file"] = "allow_always",
			["fs.write_text_file"] = "ask",
			["terminal.create"] = "ask",
			["_cog.nvim/grep"] = "allow_once",
			["_cog.nvim/apply_edits"] = "ask",
		},
		timeout_ms = 30000,
		timeout_response = "reject_once",
	},
	debug = {
		session_updates = false,
		session_updates_path = nil, -- Defaults to stdpath("cache") .. "/cog-session-updates.log"
	},
	keymaps = {
		toggle_chat = "<leader>cc",
		open_chat = nil,
		prompt = "<leader>cp",
		cancel = "<C-c>",
	},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

function M.get()
	return M.options
end

return M
