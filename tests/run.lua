-- Headless tests against the real core:
--   COMMIT_HIKE_BIN=/path/to/commit-hike nvim --headless -u NONE -l plugins/neovim/tests/run.lua
-- (task neovim:test builds the core and runs this.)
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
vim.opt.rtp:prepend(here .. "..")
vim.cmd.runtime("plugin/commit-hike.lua")

local bin = assert(os.getenv("COMMIT_HIKE_BIN"), "set COMMIT_HIKE_BIN to a built commit-hike")
local home = vim.fn.tempname()
local repo = vim.fn.tempname()
vim.env.COMMIT_HIKE_HOME = home
vim.fn.mkdir(repo, "p")

local failures, passed = 0, 0
local function check(name, cond, detail)
  if cond then
    passed = passed + 1
  else
    failures = failures + 1
    io.stderr:write("FAIL " .. name .. (detail and (": " .. vim.inspect(detail)) or "") .. "\n")
  end
end

local function sh(cmd)
  local res = vim.system(cmd, { cwd = repo, text = true, env = {
    GIT_AUTHOR_NAME = "Me", GIT_AUTHOR_EMAIL = "me@x.io", GIT_COMMITTER_NAME = "Me", GIT_COMMITTER_EMAIL = "me@x.io",
  } }):wait()
  assert(res.code == 0, table.concat(cmd, " ") .. ": " .. (res.stderr or ""))
  return res.stdout
end
local n = 0
local function commit(lines)
  n = n + 1
  local f = io.open(repo .. "/f" .. n .. ".txt", "w")
  for i = 1, lines do
    f:write("line " .. i .. "\n")
  end
  f:close()
  sh({ "git", "add", "-A" })
  sh({ "git", "commit", "-q", "-m", "c" .. n })
end

local ch = require("commit-hike")

-- distances read like the panel's
check("distance m", ch.distance(640, "uk") == "640 м", ch.distance(640, "uk"))
check("distance km uk", ch.distance(16000, "uk") == "16,0 км", ch.distance(16000, "uk"))
check("distance km de", ch.distance(34800, "de") == "34,8 km", ch.distance(34800, "de"))
check("distance long", ch.distance(2863000, "en") == "2863 km", ch.distance(2863000, "en"))

-- completion
check("complete commands", vim.deep_equal(ch.complete("d", "CommitHike d"), { "difficulty" }), ch.complete("d", "CommitHike d"))
check("complete values", vim.deep_equal(ch.complete("h", "CommitHike difficulty h"), { "hard" }), ch.complete("h", "CommitHike difficulty h"))
check("the command exists", vim.fn.exists(":CommitHike") == 2)

sh({ "git", "init", "-q", "-b", "main" })
vim.cmd.cd(repo)
ch.setup({ bin = bin, lang = "uk", interval = 0 })

-- not set up yet: the status line stays empty instead of showing an error
ch.refresh({ wait = true })
check("empty before init", ch.statusline() == "", ch.statusline())

local init = vim.system({ bin, "init", "--email", "me@x.io", "--route", "chornohora-ridge" }, { text = true }):wait()
check("core init", init.code == 0, init.stderr)
ch.refresh({ wait = true })
check("before any commit", ch.statusline() == "🥾 0 м · Заросляк", ch.statusline())

-- commits are counted on the next refresh (prompt --scan sees the new HEAD)
for _ = 1, 3 do
  commit(60)
end
ch.refresh({ wait = true })
local line = ch.statusline()
check("after commits", line:match("^🥾 %d+,%d км · ") ~= nil, line)

-- a commit made outside Neovim reaches the status line by itself (.git/logs/HEAD watcher)
local before = ch.statusline()
commit(80)
local changed = vim.wait(5000, function()
  return ch.statusline() ~= before
end, 50)
check("the watcher picks up a commit", changed, { before = before, after = ch.statusline() })

-- :CommitHike status: the lines come from the core's status
local st = vim.json.decode(vim.system({ bin, "status", "--repo", repo, "--lang", "uk" }, { text = true }):wait().stdout).data
local lines = ch.status_lines(st)
check("status: route name", lines[1]:match("Чорногірський хребет") ~= nil, lines)
check("status: walked", vim.iter(lines):any(function(l) return l:match("Пройдено: %d") ~= nil end), lines)
check("status: next stop", vim.iter(lines):any(function(l) return l:match("Наступна зупинка: ") ~= nil end), lines)

-- the commands talk to the core
local done = false
ch._core({ "difficulty", "--set", "hard" }, function(ok, data)
  done = ok and data.level == "hard"
end)
check("difficulty via the core", vim.wait(3000, function() return done end, 20))

-- a missing binary: nothing in the status line, a clear message for commands
ch.config.bin = "/nonexistent/commit-hike"
ch.refresh({ wait = true })
check("missing binary: empty status line", ch.statusline() == "", ch.statusline())
local msg
ch._core({ "status" }, function(ok, m, err)
  msg = (not ok) and err and err.code
end)
check("missing binary: reported", vim.wait(2000, function() return msg == "missing" end, 20), msg)

io.stdout:write(string.format("%d passed, %d failed\n", passed, failures))
vim.cmd(failures == 0 and "qall!" or "cquit!")
