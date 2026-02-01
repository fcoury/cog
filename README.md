# cog.nvim + cog-agent

A Neovim-first agent experience with a Rust backend. `cog.nvim` provides the UI, permissions, and editor tools; `cog-agent` speaks ACP and bridges to an external agent adapter (e.g. `codex-acp`). All agent interactions happen inside Neovim, and file changes are applied live to buffers.

## Requirements

- Neovim 0.10+
- Rust toolchain (for building `cog-agent`)
- An ACP adapter binary (default: `codex-acp`)
- Optional: `nui.nvim`, `fidget.nvim`, `render-markdown.nvim`
- Optional: `rg` (ripgrep) for `_cog.nvim/grep`

## Installation (Lazy.nvim)

Local checkout example:

```lua
{
  dir = "/Users/fcoury/code/cog/cog.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "j-hui/fidget.nvim",
    "MeanderingProgrammer/render-markdown.nvim",
  },
  config = function()
    require("cog").setup({
      backend = {
        bin_path = "/Users/fcoury/code/cog/cog-agent/target/release/cog-agent",
        auto_start = true,
      },
      adapters = {
        codex = {
          command = { "/Users/fcoury/.local/bin/codex-acp" },
        },
      },
    })
  end,
}
```

If you want to load from a git remote instead, replace `dir = ...` with `"owner/repo"` and update the `backend.bin_path` accordingly.

## Build the backend

```sh
cd /Users/fcoury/code/cog/cog-agent
cargo build --release
```

Ensure `backend.bin_path` points to the built binary.

## Adapter setup (codex-acp)

`cog.nvim` runs an ACP adapter binary and talks JSON-RPC over stdio. The default adapter is `codex-acp`.

Install a `codex-acp` binary and either:

- Put it in `$PATH`, or
- Set `adapters.codex.command = { "/absolute/path/to/codex-acp" }`

If `codex-acp` is not on PATH, `cog.nvim` also tries `~/.local/bin/codex-acp`.

## Usage

Commands:

- `:CogStart` — connect to backend + open chat
- `:CogStop` — disconnect
- `:CogChat` — open chat UI
- `:CogPrompt` — prompt input

Defaults:

- Chat opens on the right (40% width)
- Input pane uses `<C-CR>` to submit
- Permissions are prompted for writes and tools
- Diff approval is shown by default (`file_operations.auto_apply = false`)

## Configuration

All configuration options and defaults live in:

`cog.nvim/lua/cog/config.lua`

Common overrides:

```lua
require("cog").setup({
  backend = {
    bin_path = "/path/to/cog-agent",
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
      position = "right",
      width = "40%",
      border = "rounded",
      input_height = 20,
      input_submit = "<C-CR>",
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
      ["_cog.nvim/grep"] = "allow_once",
      ["_cog.nvim/apply_edits"] = "ask",
    },
    timeout_ms = 30000,
    timeout_response = "reject_once",
  },
  keymaps = {
    open_chat = "<leader>cc",
    prompt = "<leader>cp",
    cancel = "<C-c>",
  },
})
```

## Troubleshooting

### `E492: Not an editor command: CogStart`

This means the plugin isn’t loaded. Check:

1. `cog.nvim` is present in your plugin manager config.
2. You’re not using `lazy = true` without an `event` or `cmd` that loads it.
3. Your `dir` path is correct.

Example minimal Lazy spec:

```lua
{ dir = "/Users/fcoury/code/cog/cog.nvim" }
```

### Adapter not found

If the adapter binary isn’t on PATH, set:

```lua
adapters = { codex = { command = { "/absolute/path/to/codex-acp" } } }
```

### Changes not appearing

Ensure you are running Neovim 0.10+ and that `cog-agent` is the release build (`target/release/cog-agent`).

## Development

- `cog.nvim` is in `cog.nvim/`
- `cog-agent` is in `cog-agent/`

Build + test quickly:

```sh
cd /Users/fcoury/code/cog/cog-agent
cargo build
```

Run a headless sanity check:

```sh
nvim --clean -u NONE -c "set rtp+=/Users/fcoury/code/cog/cog.nvim" -c "lua require('cog').setup({ backend = { bin_path = '/Users/fcoury/code/cog/cog-agent/target/release/cog-agent' } })" -c "CogStart" -c "qa!"
```
