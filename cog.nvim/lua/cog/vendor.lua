local M = {}

local CODEX_ACP_VERSION = "0.9.0"
local GITHUB_RELEASES_URL = "https://github.com/zed-industries/codex-acp/releases/download/v" .. CODEX_ACP_VERSION

-- Cache directory for vendored binaries
local function get_cache_dir()
  local cache_dir = vim.fn.stdpath("cache") .. "/cog.nvim"
  vim.fn.mkdir(cache_dir, "p")
  return cache_dir
end

-- Get the vendored binary path
function M.get_binary_path()
  return get_cache_dir() .. "/codex-acp"
end

-- Detect the current platform
local function detect_platform()
  local os_name = vim.loop.os_uname().sysname
  local arch = vim.loop.os_uname().machine

  -- Normalize OS name
  local os_map = {
    Darwin = "apple-darwin",
    Linux = "unknown-linux-gnu",
    Windows_NT = "pc-windows-msvc",
  }

  -- Normalize architecture
  local arch_map = {
    arm64 = "aarch64",
    aarch64 = "aarch64",
    x86_64 = "x86_64",
    amd64 = "x86_64",
  }

  local normalized_os = os_map[os_name]
  local normalized_arch = arch_map[arch]

  if not normalized_os or not normalized_arch then
    return nil, string.format("Unsupported platform: %s %s", os_name, arch)
  end

  return {
    os = normalized_os,
    arch = normalized_arch,
    is_windows = os_name == "Windows_NT",
  }
end

-- Get the download URL for the current platform
local function get_download_url(platform)
  local ext = platform.is_windows and "zip" or "tar.gz"
  local filename = string.format("codex-acp-%s-%s-%s.%s",
    CODEX_ACP_VERSION, platform.arch, platform.os, ext)
  return GITHUB_RELEASES_URL .. "/" .. filename, filename
end

-- Download a file using curl
local function download_file(url, dest, callback)
  local cmd = { "curl", "-fsSL", "-o", dest, url }

  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        callback(true)
      else
        callback(false, "Download failed with exit code: " .. code)
      end
    end,
  })
end

-- Extract tar.gz file
local function extract_tgz(archive_path, dest_dir, callback)
  local cmd = { "tar", "-xzf", archive_path, "-C", dest_dir }

  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        callback(true)
      else
        callback(false, "Extraction failed with exit code: " .. code)
      end
    end,
  })
end

-- Extract zip file
local function extract_zip(archive_path, dest_dir, callback)
  local cmd = { "unzip", "-o", archive_path, "-d", dest_dir }

  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        callback(true)
      else
        callback(false, "Extraction failed with exit code: " .. code)
      end
    end,
  })
end

-- Make file executable
local function make_executable(path)
  if vim.loop.os_uname().sysname ~= "Windows_NT" then
    vim.loop.fs_chmod(path, 493) -- 0755 in decimal
  end
end

-- Check if binary is already vendored and valid
function M.is_vendored()
  local binary_path = M.get_binary_path()
  return vim.fn.executable(binary_path) == 1
end

-- Synchronous download and install (blocks until complete)
function M.install_sync()
  local platform, err = detect_platform()
  if not platform then
    return false, err
  end

  local url, filename = get_download_url(platform)
  local cache_dir = get_cache_dir()
  local archive_path = cache_dir .. "/" .. filename
  local binary_path = M.get_binary_path()

  vim.notify("cog.nvim: Downloading codex-acp for " .. platform.arch .. "-" .. platform.os .. "...", vim.log.levels.INFO)

  -- Download synchronously
  local download_cmd = { "curl", "-fsSL", "-o", archive_path, url }
  local result = vim.fn.system(download_cmd)
  if vim.v.shell_error ~= 0 then
    vim.fn.delete(archive_path, "rf")
    return false, "Failed to download: curl exited with code " .. vim.v.shell_error
  end

  vim.notify("cog.nvim: Extracting codex-acp...", vim.log.levels.INFO)

  -- Extract synchronously
  local extract_cmd
  if platform.is_windows then
    extract_cmd = { "unzip", "-o", archive_path, "-d", cache_dir }
  else
    extract_cmd = { "tar", "-xzf", archive_path, "-C", cache_dir }
  end

  result = vim.fn.system(extract_cmd)
  vim.fn.delete(archive_path, "rf")

  if vim.v.shell_error ~= 0 then
    return false, "Failed to extract archive"
  end

  -- Make executable
  make_executable(binary_path)

  -- Verify
  if vim.fn.executable(binary_path) == 0 then
    return false, "Binary not found after extraction at: " .. binary_path
  end

  vim.notify("cog.nvim: codex-acp installed successfully", vim.log.levels.INFO)
  return true
end

-- Get command array for the vendored binary
function M.get_command()
  return { M.get_binary_path() }
end

return M
