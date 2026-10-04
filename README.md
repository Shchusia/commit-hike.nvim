# commit-hike.nvim

Your commits walk a hiking trail, in your status line:

```
 main  init.lua  🥾 16,0 км · Озеро Несамовите   utf-8  lua
```

A thin wrapper around `commit-hike`, the same core as the
[Commit Hike](https://github.com/Shchusia/Commit-Hike) plugins for JetBrains
IDEs and VS Code (they share your progress). Ten routes, from the Carpathians
to the Camino, in English, Ukrainian, Polish, German and Spanish. Nothing
leaves your computer.

## Install

Neovim 0.10+. First the core (Linux, macOS; Windows: see the
[terminal guide](https://github.com/Shchusia/Commit-Hike/blob/master/docs/terminal.md)):

```sh
curl -fsSL https://raw.githubusercontent.com/Shchusia/Commit-Hike/master/scripts/install.sh | sh
```

Then the plugin. With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "Shchusia/commit-hike.nvim", version = "*", opts = {} }
```

`version = "*"` keeps you on released versions. vim-plug:
`Plug 'Shchusia/commit-hike.nvim', { 'tag': '*' }` and
`lua require("commit-hike").setup()` after `plug#end()`.

Show it in your status line, e.g. with lualine:

```lua
require("lualine").setup({
  sections = { lualine_x = { require("commit-hike").statusline, "encoding", "filetype" } },
})
```

or without plugins: `set statusline+=%{v:lua.require'commit-hike'.statusline()}`.

## Use

`:CommitHike` shows where you are; `:CommitHike scan`, `:CommitHike route`,
`:CommitHike difficulty`, `:CommitHike lang` and `:CommitHike init` do what
they say. Commits made anywhere (the terminal, fugitive, lazygit) reach the
status line within a second. `:help commit-hike` has the details and
`:checkhealth commit-hike` checks the setup.

## Where it lives

`Shchusia/commit-hike.nvim` is a read-only copy of
[`plugins/neovim`](https://github.com/Shchusia/Commit-Hike/tree/master/plugins/neovim)
in the main repository, published with every release. Issues and pull requests
go [there](https://github.com/Shchusia/Commit-Hike/issues). Tests run against
the real core in a headless Neovim: `task neovim:test`.

MIT license.
