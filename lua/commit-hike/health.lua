-- :checkhealth commit-hike
local M = {}

function M.check()
  local h = vim.health
  h.start("commit-hike")
  if vim.fn.has("nvim-0.10") == 0 then
    h.error("Neovim 0.10 or newer is needed (vim.system)")
  else
    h.ok("Neovim " .. tostring(vim.version()))
  end
  local bin = require("commit-hike").config.bin
  if vim.fn.executable(bin) == 0 then
    h.error(bin .. " not found", {
      "Install it: curl -fsSL https://raw.githubusercontent.com/Shchusia/Commit-Hike/master/scripts/install.sh | sh",
      "or set bin = '/path/to/commit-hike' in setup()",
    })
    return
  end
  local res = vim.system({ bin, "version" }, { text = true }):wait()
  local ok, env = pcall(vim.json.decode, res.stdout or "")
  if ok and env.ok then
    h.ok(string.format("%s %s (protocol %s)", bin, env.data.version, env.data.api))
  else
    h.warn("couldn't read the version of " .. bin)
  end
  local cfg = vim.system({ bin, "config" }, { text = true }):wait()
  local okc, conf = pcall(vim.json.decode, cfg.stdout or "")
  if okc and conf.ok then
    h.ok("set up for " .. table.concat(conf.data.emails or {}, ", "))
  else
    h.warn("not set up yet", { "Run :CommitHike init" })
  end
end

return M
