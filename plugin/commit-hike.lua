-- :CommitHike [status|scan|route [id]|difficulty [level]|lang [code]|init]
-- The status line and the background refresh start with require("commit-hike").setup().
if vim.g.loaded_commit_hike then
  return
end
vim.g.loaded_commit_hike = true

vim.api.nvim_create_user_command("CommitHike", function(opts)
  require("commit-hike").run(opts.fargs)
end, {
  nargs = "*",
  desc = "Commit Hike: your commits walk a hiking trail",
  complete = function(arglead, cmdline)
    return require("commit-hike").complete(arglead, cmdline)
  end,
})
