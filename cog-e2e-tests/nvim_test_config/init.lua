-- Minimal neovim config for E2E testing of cog.nvim
-- This config loads cog.nvim with settings optimized for automated testing

-- Paths (hardcoded for reliability in testing)
local project_root = "/Volumes/External/code-external/cog"
local cog_nvim_path = project_root .. "/cog.nvim"
local cog_agent_path = project_root .. "/cog-agent/target/debug/cog-agent"

-- Add cog.nvim to runtime path (in case not already added via --cmd)
vim.opt.runtimepath:prepend(cog_nvim_path)

-- Disable some features that interfere with testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.updatetime = 300
vim.opt.timeoutlen = 3000  -- Longer timeout for leader key sequences
vim.opt.ttimeoutlen = 10

-- Set leader key to space (matching default keymaps)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Setup cog.nvim with test-friendly settings
require("cog").setup({
    backend = {
        bin_path = cog_agent_path,
        log_level = "debug",
        auto_start = true,
    },
    adapter = "codex",
    adapters = {
        codex = {
            command = { "codex-acp" },
            env = {},
        },
    },
    ui = {
        chat = {
            layout = "vsplit",
            position = "right",
            width = "40%",
            border = "rounded",
            input_height = 5,
            input_send_on_enter = true,
            pending_message = "Thinking...",
            pending_timeout_ms = 60000, -- Longer timeout for testing
            pending_timeout_message = "No response yet; still waiting...",
            disable_input_while_waiting = true,
        },
    },
    file_operations = {
        auto_apply = true, -- Auto-apply for testing (no confirmation needed)
        auto_save = true,
        animate = false, -- Disable animation for faster testing
        animate_delay_ms = 0,
    },
    permissions = {
        defaults = {
            ["fs.read_text_file"] = "allow_always",
            ["fs.write_text_file"] = "allow_always", -- Auto-allow for testing
            ["terminal.create"] = "allow_always",
            ["_cog.nvim/grep"] = "allow_always",
            ["_cog.nvim/apply_edits"] = "allow_always", -- Auto-allow for testing
        },
        timeout_ms = 60000, -- Longer timeout
        timeout_response = "allow_once", -- Allow on timeout for testing
    },
    debug = {
        session_updates = true,
        session_updates_path = "/tmp/cog-e2e-session-updates.log",
    },
    keymaps = {
        toggle_chat = "<leader>cc",
        open_chat = nil,
        prompt = "<leader>cp",
        cancel = "<C-c>",
    },
})

-- Print startup message for debugging
vim.defer_fn(function()
    vim.notify("cog.nvim E2E test config loaded", vim.log.levels.INFO)
end, 100)
