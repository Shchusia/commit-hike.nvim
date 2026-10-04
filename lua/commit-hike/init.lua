-- Commit Hike for Neovim: your commits walk a hiking trail.
--
-- A thin wrapper around the `commit-hike` program (the same core the IDE
-- plugins use): the status line text comes from `commit-hike prompt`, the
-- commands call the core's JSON commands. Nothing here blocks the editor.
local M = {}

local uv = vim.uv or vim.loop

M.config = {
  bin = "commit-hike", -- the core; install: curl -fsSL https://raw.githubusercontent.com/Shchusia/Commit-Hike/master/scripts/install.sh | sh
  icon = "🥾", -- before the distance in the status line; "" for none
  lang = nil, -- nil: the language set in Commit Hike, else the editor's
  interval = 60, -- seconds between background refreshes; 0 turns them off
  watch_head = true, -- refresh right after a commit (watches .git/logs/HEAD)
}

local state = {
  text = "", -- what statusline() returns
  root = nil, -- git work tree of the current folder
  watcher = nil,
  watched = nil,
  timer = nil,
  running = false,
  again = false, -- a refresh was asked for while one was running
}

-- ---------------------------------------------------------------- texts
-- Labels of :CommitHike status. Route texts come translated from the core.
local TEXTS = {
  en = {
    title = "Commit Hike", walked = "Walked", place = "You are at", next = "Next stop", today = "Today", streak = "Streak",
    altitude = "Altitude", finished = "Trail completed", days = "%d days", noJourney = "No trail yet: run :CommitHike route",
    notSetUp = "Commit Hike isn't set up yet: run :CommitHike init", missing = "commit-hike isn't installed: see :help commit-hike-install",
    pickRoute = "Choose a trail", history = "Count the commits you already made?", yes = "Yes, from the start of the history",
    no = "No, from now on", pickDifficulty = "Difficulty", pickLang = "Language", auto = "Same as the editor",
    scanned = "Counted %d new commits", initDone = "Commit Hike is set up for %s",
  },
  uk = {
    title = "Commit Hike", walked = "Пройдено", place = "Ти тут", next = "Наступна зупинка", today = "Сьогодні", streak = "Серія",
    altitude = "Висота", finished = "Стежку пройдено", days = "%d дн.", noJourney = "Стежку ще не вибрано: :CommitHike route",
    notSetUp = "Commit Hike ще не налаштовано: :CommitHike init", missing = "commit-hike не встановлено: див. :help commit-hike-install",
    pickRoute = "Вибери стежку", history = "Рахувати вже зроблені коміти?", yes = "Так, від початку історії",
    no = "Ні, відтепер", pickDifficulty = "Складність", pickLang = "Мова", auto = "Як у редакторі",
    scanned = "Пораховано нових комітів: %d", initDone = "Commit Hike налаштовано для %s",
  },
  pl = {
    title = "Commit Hike", walked = "Przebyto", place = "Jesteś tutaj", next = "Następny przystanek", today = "Dzisiaj", streak = "Seria",
    altitude = "Wysokość", finished = "Szlak ukończony", days = "%d dni", noJourney = "Nie wybrano szlaku: :CommitHike route",
    notSetUp = "Commit Hike nie jest jeszcze skonfigurowany: :CommitHike init", missing = "commit-hike nie jest zainstalowany: zob. :help commit-hike-install",
    pickRoute = "Wybierz szlak", history = "Liczyć już zrobione commity?", yes = "Tak, od początku historii",
    no = "Nie, od teraz", pickDifficulty = "Poziom trudności", pickLang = "Język", auto = "Jak w edytorze",
    scanned = "Policzono nowych commitów: %d", initDone = "Commit Hike skonfigurowany dla %s",
  },
  de = {
    title = "Commit Hike", walked = "Gewandert", place = "Du bist hier", next = "Nächster Halt", today = "Heute", streak = "Serie",
    altitude = "Höhe", finished = "Weg geschafft", days = "%d Tage", noJourney = "Noch kein Weg gewählt: :CommitHike route",
    notSetUp = "Commit Hike ist noch nicht eingerichtet: :CommitHike init", missing = "commit-hike ist nicht installiert: siehe :help commit-hike-install",
    pickRoute = "Weg wählen", history = "Schon gemachte Commits mitzählen?", yes = "Ja, ab Beginn der Historie",
    no = "Nein, ab jetzt", pickDifficulty = "Schwierigkeit", pickLang = "Sprache", auto = "Wie im Editor",
    scanned = "Neue Commits gezählt: %d", initDone = "Commit Hike ist eingerichtet für %s",
  },
  es = {
    title = "Commit Hike", walked = "Recorrido", place = "Estás en", next = "Próxima parada", today = "Hoy", streak = "Racha",
    altitude = "Altitud", finished = "Ruta completada", days = "%d días", noJourney = "Aún no hay ruta: :CommitHike route",
    notSetUp = "Commit Hike aún no está configurado: :CommitHike init", missing = "commit-hike no está instalado: ver :help commit-hike-install",
    pickRoute = "Elige una ruta", history = "¿Contar los commits que ya hiciste?", yes = "Sí, desde el inicio del historial",
    no = "No, desde ahora", pickDifficulty = "Dificultad", pickLang = "Idioma", auto = "Como el editor",
    scanned = "Commits nuevos contados: %d", initDone = "Commit Hike configurado para %s",
  },
}
local LEVELS = { easy = { "Easy", "Легка", "Łatwy", "Leicht", "Fácil" }, medium = { "Medium", "Середня", "Średni", "Mittel", "Media" },
  hard = { "Hard", "Складна", "Trudny", "Schwer", "Difícil" } }
local LANG_INDEX = { en = 1, uk = 2, pl = 3, de = 4, es = 5 }
local LANG_NAMES = { en = "English", uk = "Українська", pl = "Polski", de = "Deutsch", es = "Español" }

--- The editor's language as a two-letter code ("uk" from "uk_UA.UTF-8").
local function editor_lang()
  if M.config.lang then
    return M.config.lang
  end
  for _, v in ipairs({ vim.env.LC_ALL, vim.env.LC_MESSAGES, vim.env.LANG, vim.v.lang }) do
    local code = v and v:match("^(%a%a%a?)[_%-%.@]?") or nil
    if code and code ~= "C" then
      return code:lower()
    end
  end
  return "en"
end

local function texts(locale)
  local base = (locale or editor_lang()):match("^(%a+)") or "en"
  return TEXTS[base] or TEXTS.en, base
end

--- Distances as the panel writes them: 640 m · 16,0 км · 2863 km.
function M.distance(m, locale)
  local base = (locale or "en"):match("^(%a+)") or "en"
  local unit_m, unit_km = "m", "km"
  local comma = base == "uk" or base == "pl" or base == "de" or base == "es"
  if base == "uk" then
    unit_m, unit_km = "м", "км"
  end
  m = math.max(0, m or 0)
  if m < 1000 then
    return string.format("%d %s", math.floor(m + 0.5), unit_m)
  end
  local km = m / 1000
  if km >= 100 then
    return string.format("%d %s", math.floor(km + 0.5), unit_km)
  end
  local s = string.format("%.1f", km)
  if comma then
    s = s:gsub("%.", ",")
  end
  return s .. " " .. unit_km
end

-- ---------------------------------------------------------------- the core
--- Runs the core. cb(ok, data_or_message) gets the decoded envelope's data.
local function core(args, cb)
  local cmd = { M.config.bin }
  vim.list_extend(cmd, args)
  local ok, err = pcall(vim.system, cmd, { text = true }, function(res)
    vim.schedule(function()
      local parsed, decoded = pcall(vim.json.decode, res.stdout or "")
      if not parsed or type(decoded) ~= "table" then
        cb(false, (res.stderr ~= "" and res.stderr) or ("exit " .. tostring(res.code)))
      elseif decoded.ok then
        cb(true, decoded.data)
      else
        cb(false, decoded.error and (decoded.error.code .. ": " .. decoded.error.message) or "error", decoded.error)
      end
    end)
  end)
  if not ok then -- the binary isn't installed
    vim.schedule(function()
      cb(false, texts().missing .. " (" .. tostring(err) .. ")", { code = "missing" })
    end)
  end
end
M._core = core

local function repo_root(dir)
  local found = vim.fs.find(".git", { path = dir, upward = true })[1]
  return found and vim.fs.dirname(found) or nil
end

-- ---------------------------------------------------------------- status line
local function redraw()
  pcall(vim.cmd.redrawstatus)
end

--- Asks the core for the line; counts new commits first when HEAD moved.
--- opts.wait = true runs synchronously (for tests and :CommitHike scan).
function M.refresh(opts)
  opts = opts or {}
  if state.running and not opts.wait then
    state.again = true
    return
  end
  local dir = vim.fn.getcwd()
  state.root = repo_root(dir)
  M._watch(state.root)
  local cmd = { M.config.bin, "prompt", "--scan", "--repo", dir, "--icon", M.config.icon }
  if M.config.lang then
    vim.list_extend(cmd, { "--lang", M.config.lang })
  end
  state.running = true
  local function done(res)
    state.running = false
    local line = (res.code == 0 and res.stdout or ""):gsub("%s+$", "")
    if line ~= state.text then
      state.text = line
      vim.schedule(redraw)
    end
    if state.again then
      state.again = false
      vim.schedule(M.refresh)
    end
  end
  local ok, job = pcall(vim.system, cmd, { text = true }, (not opts.wait) and done or nil)
  if not ok then
    state.running = false
    state.text = ""
    return
  end
  if opts.wait then
    done(job:wait())
  end
end

--- The text for a status line, e.g. "🥾 16,0 км · Озеро Несамовите". Never blocks.
function M.statusline()
  return state.text
end

-- Watch .git/logs/HEAD: every commit, checkout or rebase appends to it, from
-- any tool. One watcher for the current work tree.
function M._watch(root)
  if not M.config.watch_head or root == state.watched then
    return
  end
  if state.watcher then
    state.watcher:stop()
    state.watcher = nil
  end
  state.watched = nil -- set only once a watcher runs: a new repository has no logs/ until its first commit
  local gitdir = root and (root .. "/.git") or nil
  if gitdir and vim.fn.isdirectory(gitdir) == 0 then
    -- a worktree or submodule: .git is a file "gitdir: <path>"
    local f = io.open(gitdir, "r")
    local line = f and f:read("*l") or ""
    if f then
      f:close()
    end
    gitdir = line:match("^gitdir:%s*(.+)$")
  end
  local logs = gitdir and (gitdir .. "/logs") or nil
  if not logs or vim.fn.isdirectory(logs) == 0 then
    return
  end
  local w = uv.new_fs_event()
  if not w then
    return
  end
  local pending = false
  w:start(logs, {}, function(_, fname)
    if fname ~= "HEAD" or pending then
      return
    end
    pending = true -- git writes several times per commit: one refresh
    vim.defer_fn(function()
      pending = false
      M.refresh()
    end, 700)
  end)
  state.watcher = w
  state.watched = root
end

-- ---------------------------------------------------------------- commands
local function float(lines)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded", title = " 🥾 Commit Hike ", title_pos = "center",
    width = width + 2, height = #lines,
    row = math.floor((vim.o.lines - #lines) / 2) - 1, col = math.floor((vim.o.columns - width) / 2),
  })
  for _, key in ipairs({ "q", "<Esc>", "<CR>" }) do
    vim.keymap.set("n", key, function()
      pcall(vim.api.nvim_win_close, win, true)
    end, { buffer = buf, nowait = true })
  end
  return buf, win
end

--- The lines of :CommitHike status for a status answer of the core.
function M.status_lines(st)
  local T = texts(st.locale)
  local j = st.project or st.global
  if not j then
    return { T.noJourney }
  end
  local d = function(m)
    return M.distance(m, st.locale)
  end
  local lines = { " " .. j.route.name, "" }
  local pct = string.format("%.1f%%", j.percent or 0)
  if st.locale and st.locale:match("^%a+") ~= "en" then
    pct = pct:gsub("%.", ",")
  end
  table.insert(lines, string.format(" %s: %s / %s (%s)", T.walked, d(j.distance_m), d(j.route.length_m), pct))
  if j.finished then
    table.insert(lines, " " .. T.finished .. " ✓")
  else
    if j.last_waypoint then
      table.insert(lines, string.format(" %s: %s", T.place, j.last_waypoint.name))
    end
    if j.next_waypoint then
      table.insert(lines, string.format(" %s: %s · %s", T.next, j.next_waypoint.name, d(j.to_next_m or 0)))
    end
  end
  if j.elevation_m then
    local unit = (st.locale or ""):match("^uk") and "м" or "m"
    table.insert(lines, string.format(" %s: %d %s", T.altitude, math.floor(j.elevation_m + 0.5), unit))
  end
  table.insert(lines, string.format(" %s: %s · %s: " .. T.days, T.today, d(st.today_m or 0), T.streak, j.streak_days or 0))
  return lines
end

local function report(msg, err)
  local T = texts()
  if err and err.code == "not_initialized" then
    msg = T.notSetUp
  end
  vim.notify(msg, vim.log.levels.WARN, { title = "Commit Hike" })
end

local function lang_args()
  return M.config.lang and { "--lang", M.config.lang } or { "--lang", editor_lang() }
end

local commands = {}

function commands.status()
  local args = { "status", "--repo", vim.fn.getcwd() }
  vim.list_extend(args, lang_args())
  core(args, function(ok, data, err)
    if not ok then
      return report(data, err)
    end
    float(M.status_lines(data))
  end)
end

function commands.scan()
  local root = repo_root(vim.fn.getcwd())
  if not root then
    return report(texts().noJourney)
  end
  local args = { "scan", "--repo", root }
  vim.list_extend(args, lang_args())
  core(args, function(ok, data, err)
    if not ok then
      return report(data, err)
    end
    vim.notify(string.format(texts(data.locale).scanned, data.new_commits or 0), vim.log.levels.INFO, { title = "Commit Hike" })
    M.refresh()
  end)
end

function commands.init()
  local email = vim.trim(vim.fn.system({ "git", "config", "--global", "user.email" }))
  vim.ui.input({ prompt = "E-mail: ", default = email }, function(input)
    if not input or input == "" then
      return
    end
    core({ "init", "--email", input }, function(ok, data, err)
      if not ok then
        return report(data, err)
      end
      vim.notify(string.format(texts().initDone, input), vim.log.levels.INFO, { title = "Commit Hike" })
      M.refresh()
    end)
  end)
end

function commands.route(id)
  local function walk(route_id)
    local T = texts()
    vim.ui.select({ true, false }, {
      prompt = T.history,
      format_item = function(v)
        return v and T.yes or T.no
      end,
    }, function(history)
      if history == nil then
        return
      end
      core({ "journey", "--scope", "global", "--route", route_id, "--from-history=" .. tostring(history) }, function(ok, data, err)
        if not ok then
          return report(data, err)
        end
        M.refresh()
        commands.status()
      end)
    end)
  end
  if id and id ~= "" then
    return walk(id)
  end
  local args = { "routes" }
  vim.list_extend(args, lang_args())
  core(args, function(ok, routes, err)
    if not ok then
      return report(routes, err)
    end
    vim.ui.select(routes, {
      prompt = texts().pickRoute,
      format_item = function(r)
        return string.format("%s · %s", r.name, M.distance(r.length_m, editor_lang()))
      end,
    }, function(r)
      if r then
        walk(r.id)
      end
    end)
  end)
end

function commands.difficulty(level)
  local function set(l)
    core({ "difficulty", "--set", l }, function(ok, data, err)
      if not ok then
        return report(data, err)
      end
      M.refresh()
    end)
  end
  if level and level ~= "" then
    return set(level)
  end
  local _, base = texts()
  vim.ui.select({ "easy", "medium", "hard" }, {
    prompt = texts().pickDifficulty,
    format_item = function(l)
      return LEVELS[l][LANG_INDEX[base] or 1]
    end,
  }, function(l)
    if l then
      set(l)
    end
  end)
end

function commands.lang(code)
  local function set(c)
    core({ "locale", "--set", c }, function(ok, data, err)
      if not ok then
        return report(data, err)
      end
      M.refresh()
    end)
  end
  if code and code ~= "" then
    return set(code)
  end
  vim.ui.select({ "auto", "en", "uk", "pl", "de", "es" }, {
    prompt = texts().pickLang,
    format_item = function(c)
      return c == "auto" and texts().auto or LANG_NAMES[c]
    end,
  }, function(c)
    if c then
      set(c)
    end
  end)
end

M.commands = commands

local VALUES = {
  difficulty = { "easy", "medium", "hard" },
  lang = { "auto", "en", "uk", "pl", "de", "es" },
}

function M.complete(arglead, cmdline)
  local words = vim.split(cmdline, "%s+", { trimempty = true })
  local typing_first = #words == 1 or (#words == 2 and not cmdline:match("%s$"))
  local pool = typing_first and vim.tbl_keys(commands) or (VALUES[words[2]] or {})
  table.sort(pool)
  return vim.tbl_filter(function(v)
    return v:sub(1, #arglead) == arglead
  end, pool)
end

function M.run(args)
  local name, value = args[1] or "status", args[2]
  local fn = commands[name]
  if not fn then
    return vim.notify("Commit Hike: unknown command " .. name, vim.log.levels.ERROR)
  end
  fn(value)
end

-- ---------------------------------------------------------------- setup
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  -- Also here, not only in plugin/: plugin managers that add plugins/neovim to
  -- the runtimepath after start-up (lazy.nvim's config) never source plugin/.
  if vim.fn.exists(":CommitHike") ~= 2 then
    vim.api.nvim_create_user_command("CommitHike", function(o)
      M.run(o.fargs)
    end, { nargs = "*", desc = "Commit Hike: your commits walk a hiking trail", complete = M.complete })
  end
  local group = vim.api.nvim_create_augroup("CommitHike", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "FocusGained" }, {
    group = group,
    callback = function()
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if state.watcher then
        state.watcher:stop()
      end
      if state.timer then
        state.timer:stop()
      end
    end,
  })
  if state.timer then
    state.timer:stop()
    state.timer = nil
  end
  if (M.config.interval or 0) > 0 then
    state.timer = uv.new_timer()
    state.timer:start(M.config.interval * 1000, M.config.interval * 1000, vim.schedule_wrap(M.refresh))
  end
  if vim.v.vim_did_enter == 1 then
    M.refresh()
  end
end

return M
