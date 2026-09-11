local config = require("preview.config")
local log = require("preview.log")
local state = require("preview.state")
local highlights = require("preview.ui.highlights")
local winbar = require("preview.ui.winbar")
local render = require("preview.render")

local M = {}

---@type preview.Config|nil
local cfg = nil
local AUGROUP = "preview.nvim"
---@type string[]
local SUBCOMMANDS = { "toggle", "preview", "markdown" }
local KEYMAP_DESC = "[T]oggle [P]review"
local KEYMAP_RHS = "<Cmd>lua require('preview').toggle()<CR>"

-- Pure helpers ---------------------------------------------------------------

---@param mode preview.Mode
---@return preview.Mode
local function other_mode(mode)
  return mode == "preview" and "markdown" or "preview"
end

---@param arg string
---@return boolean
local function is_subcommand(arg)
  return vim.tbl_contains(SUBCOMMANDS, arg)
end

--- File names decide eligibility; unnamed Markdown buffers still work.
---@param buf integer
---@return boolean
local function is_markdown(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return vim.bo[buf].filetype == "markdown"
  end
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  local extension = name:match("%.([^./]+)$")
  extension = extension and extension:lower()
  return extension == "md" or extension == "markdown"
end

--- Decides whether the renderer must attach to or detach from a buffer, given
--- whether it is attached now and how many of its windows are in preview mode.
---@param attached boolean
---@param preview_count integer
---@return "attach"|"detach"|nil
local function attachment_change(attached, preview_count)
  if not attached and preview_count > 0 then
    return "attach"
  end
  if attached and preview_count == 0 then
    return "detach"
  end
  return nil
end

--- The winbar value worth restoring on release. A window split from a managed
--- one inherits our expression; restoring that would leave an empty bar behind.
---@param current string
---@return string
local function restorable_winbar(current)
  return current == winbar.EXPR and "" or current
end

--- The window options preview mode applies. 'wrap' stays as the user's setup
--- left it unless view.wrap forces it; layout emulates word wrapping, so
--- native break options stay off.
---@return table<string, any>
local function preview_options()
  return {
    conceallevel = 2,
    concealcursor = "nvic",
    number = false,
    relativenumber = false,
    signcolumn = "no",
    cursorline = false,
    colorcolumn = "",
    foldcolumn = "0",
    foldenable = false,
    linebreak = false,
    breakindent = false,
    breakindentopt = "",
    showbreak = "",
    list = false,
    wrap = cfg and cfg.view.wrap,
  }
end

--- Options preview snapshots. 'wrap' is always saved, so a setup() that starts
--- forcing it mid-preview can still restore the window's own value.
---@return string[]
local function saved_keys()
  local keys = vim.tbl_keys(preview_options())
  if not vim.list_contains(keys, "wrap") then keys[#keys + 1] = "wrap" end
  return keys
end

--- Saved options to reapply; the saved 'wrap' only while view.wrap forces it.
---@param saved table<string, any>
---@return table<string, any>
local function restorable(saved)
  if cfg and cfg.view.wrap ~= nil then return saved end
  local out = vim.deepcopy(saved)
  out.wrap = nil
  return out
end

--- Keep inherited raw options; undo preview options using the source baseline.
---@param current table<string, any>
---@param source preview.WindowState|nil
---@return table<string, any>
local function baseline_options(current, source)
  return source and source.mode == "preview"
    and vim.deepcopy(source.saved_options) or current
end

--- Subcommands matching the typed prefix, for command completion.
---@param arglead string
---@return string[]
local function complete_subcommand(arglead)
  return vim.tbl_filter(function(sub)
    return vim.startswith(sub, arglead)
  end, SUBCOMMANDS)
end

-- Effectful helpers ----------------------------------------------------------

---@param win integer
---@param keys string[]
---@return table<string, any>
local function snapshot_options(win, keys)
  local out = {}
  for _, key in ipairs(keys) do
    out[key] = vim.wo[win][key]
  end
  return out
end

---@param win integer
---@param options table<string, any>
local function apply_options(win, options)
  for key, value in pairs(options) do
    vim.wo[win][key] = value
  end
end

--- Only the two bar mappings belong to this plugin.
---@param win integer
---@return table<string, string>
local function bar_mappings(win)
  local saved = { WinBar = "", WinBarNC = "" }
  for item in vim.wo[win].winhighlight:gmatch("[^,]+") do
    local from, to = item:match("^([^:]+):(.+)$")
    if saved[from] ~= nil then
      saved[from] = to
    end
  end
  return saved
end

---@param win integer
---@param values table<string, string>
---@param restoring boolean|nil
local function set_bar_mappings(win, values, restoring)
  local parts, current = {}, bar_mappings(win)
  for item in vim.wo[win].winhighlight:gmatch("[^,]+") do
    local from = item:match("^([^:]+):")
    if values[from] == nil then
      parts[#parts + 1] = item
    end
  end
  for _, from in ipairs({ "WinBar", "WinBarNC" }) do
    local to = restoring and current[from] ~= "Normal" and current[from] or values[from]
    if to and to ~= "" then
      parts[#parts + 1] = from .. ":" .. to
    end
  end
  vim.wo[win].winhighlight = table.concat(parts, ",")
end

---@type table<integer, { raw_lhs: string }>
local keymaps = {}

---@param buf integer
---@param force boolean|nil
local function cleanup_keymap(buf, force)
  local owned = keymaps[buf]
  if not owned then
    return
  end
  if not force then
    for _, entry in pairs(state.snapshot().windows) do
      if entry.buf == buf then
        return
      end
    end
  end
  if vim.api.nvim_buf_is_valid(buf) then
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if mapping.lhsraw == owned.raw_lhs and mapping.rhs == KEYMAP_RHS and mapping.desc == KEYMAP_DESC then
        vim.keymap.del("n", mapping.lhs, { buffer = buf })
        break
      end
    end
  end
  keymaps[buf] = nil
end

---@param buf integer
local function install_keymap(buf)
  if not cfg then
    return
  end
  local raw_lhs = cfg.keymap ~= false
    and vim.api.nvim_replace_termcodes(cfg.keymap, true, true, true) or nil
  if keymaps[buf] and keymaps[buf].raw_lhs ~= raw_lhs then
    cleanup_keymap(buf, true)
  end
  if not raw_lhs or keymaps[buf] then
    return
  end
  vim.keymap.set("n", cfg.keymap, KEYMAP_RHS, { buffer = buf, desc = KEYMAP_DESC })
  keymaps[buf] = { raw_lhs = raw_lhs }
end

---@param buf integer
local function sync_attachment(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local change = attachment_change(state.is_attached(buf), #state.preview_windows_for(buf))
  if change == "attach" then
    render.attach(buf)
  elseif change == "detach" then
    render.detach(buf)
  end
end

---@param win integer
local function redraw(win)
  pcall(vim.api.nvim__redraw, { win = win, valid = false })
end

---@param win integer
---@param entry preview.WindowState
local function restore_bar(win, entry)
  if vim.wo[win].winbar == winbar.EXPR then
    vim.wo[win].winbar = entry.saved_winbar
  end
  set_bar_mappings(win, entry.saved_bar_mappings, true)
end

--- Never apply one buffer's baseline to the next buffer in its window.
---@param win integer
---@param entry preview.WindowState
local function restore_options(win, entry)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= entry.buf or entry.suspended then
    return
  end
  if entry.bar_managed then
    restore_bar(win, entry)
  end
  if entry.mode == "preview" then
    apply_options(win, restorable(entry.saved_options))
  end
end

---@param win integer
---@param closing boolean|nil
local function release_window(win, closing)
  local entry = state.drop_window(win)
  render.release(win)
  if not entry then
    return
  end
  if not closing then
    restore_options(win, entry)
  end
  sync_attachment(entry.buf)
  cleanup_keymap(entry.buf)
end

---@param win integer
---@param entry preview.WindowState
local function apply_entry(win, entry)
  if not cfg then
    return
  end
  if entry.bar_managed ~= cfg.winbar.enabled then
    if cfg.winbar.enabled then
      entry.saved_winbar = restorable_winbar(vim.wo[win].winbar)
      entry.saved_bar_mappings = bar_mappings(win)
    elseif not entry.suspended then
      restore_bar(win, entry)
    end
    entry.bar_managed = cfg.winbar.enabled
  end
  if entry.mode == "preview" then
    apply_options(win, preview_options())
  elseif entry.suspended then
    apply_options(win, restorable(entry.saved_options))
  end
  if entry.bar_managed then
    vim.wo[win].winbar = winbar.EXPR
    set_bar_mappings(win, { WinBar = "Normal", WinBarNC = "Normal" })
  end
  entry.suspended = false
  state.set_window(win, entry)
  install_keymap(entry.buf)
  sync_attachment(entry.buf)
end

--- Reconcile the actual window/buffer binding, not just the window's mode.
---@param win integer
---@param source_win integer|nil
local function sync_window(win, source_win)
  if not cfg or not vim.api.nvim_win_is_valid(win) then
    return
  end
  -- Buffer APIs may run FileType/BufFilePost in a temporary autocmd window.
  -- It is not an editor view and disappears without a matching WinClosed.
  if vim.fn.win_gettype(win) == "autocmd" then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local entry = state.get_window(win)
  local mode = entry and entry.mode or cfg.default_mode
  -- Floats belong to whoever opened them, e.g. an LSP hover sized to its text.
  local eligible = is_markdown(buf) and vim.fn.win_gettype(win) ~= "popup"
  if entry and (entry.buf ~= buf or not eligible) then
    release_window(win)
    entry = nil
  end
  if not eligible then
    return
  end
  if not entry then
    local source = source_win and state.get_window(source_win)
    if source and source.buf ~= buf then
      source = nil
    end
    local keys = saved_keys()
    entry = {
      buf = buf,
      mode = mode,
      saved_options = baseline_options(snapshot_options(win, keys), source),
      saved_winbar = source and source.bar_managed
        and source.saved_winbar or restorable_winbar(vim.wo[win].winbar),
      saved_bar_mappings = source and source.bar_managed
        and vim.deepcopy(source.saved_bar_mappings) or bar_mappings(win),
      bar_managed = cfg.winbar.enabled,
    }
    -- A split can inherit the source window's preview options.
    apply_options(win, restorable(entry.saved_options))
  end
  apply_entry(win, entry)
end

local reconciliation_pending = false
local function reconcile_later()
  if reconciliation_pending then
    return
  end
  reconciliation_pending = true
  vim.schedule(function()
    reconciliation_pending = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      sync_window(win)
    end
  end)
end

--- BufLeave precedes remembering this buffer's window options. It also fires
--- on focus changes, so marks and the view stay for resume_suspended.
---@param buf integer
local function suspend_buffer(buf)
  for win, entry in pairs(state.snapshot().windows) do
    if entry.buf == buf and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      -- Raw options may have changed since the window was first managed.
      if entry.mode == "markdown" then
        entry.saved_options = snapshot_options(win, saved_keys())
      end
      entry.view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
      restore_options(win, entry)
      entry.suspended = true
      state.set_window(win, entry)
    end
  end
  reconcile_later()
end

--- Focus changes fire BufLeave too. Resume windows that kept their buffer before
--- the next redraw, and undo the scroll Neovim applied to them while raw.
local function resume_suspended()
  for win, entry in pairs(state.snapshot().windows) do
    if entry.suspended and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == entry.buf then
      sync_window(win)
      vim.api.nvim_win_call(win, function() vim.fn.winrestview(entry.view) end)
    end
  end
end

---@param buf integer
local function sync_windows_for(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      sync_window(win)
    end
  end
end

local function create_autocmds()
  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  local function on(event, pattern, callback)
    vim.api.nvim_create_autocmd(event, { group = group, pattern = pattern, callback = callback })
  end
  on("BufLeave", "*", function(args) suspend_buffer(args.buf) end)
  on("BufEnter", "*", resume_suspended)
  on({ "FileType", "BufEnter", "BufWinEnter", "BufFilePost" }, "*", function(args)
    sync_windows_for(args.buf)
    reconcile_later()
  end)
  local split_source
  on({ "WinNewPre", "WinLeave" }, "*", function()
    split_source = vim.api.nvim_get_current_win()
  end)
  on("WinEnter", "*", function()
    split_source = nil
  end)
  on("WinNew", "*", function()
    local source = split_source
    split_source = nil
    if not source then
      local alternate = vim.fn.win_getid(vim.fn.winnr("#"))
      source = alternate ~= 0 and alternate or nil
    end
    sync_window(vim.api.nvim_get_current_win(), source)
  end)
  on("WinClosed", "*", function(args)
    local win = tonumber(args.match)
    if win then release_window(win, true) end
  end)
  on("BufWipeout", "*", function(args)
    -- The first :write also emits BufWipeout while naming an unnamed buffer.
    -- Defer until Neovim has finished so that save retains the selected mode.
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(args.buf) and vim.api.nvim_buf_is_loaded(args.buf) then
        sync_windows_for(args.buf)
        return
      end
      for win, entry in pairs(state.snapshot().windows) do
        if entry.buf == args.buf then release_window(win) end
      end
      render.detach(args.buf)
      cleanup_keymap(args.buf)
    end)
  end)
  -- Derive after the user's palette callbacks have repainted.
  on("ColorScheme", "*", function() vim.schedule(highlights.apply) end)
  on("OptionSet", "background", function() vim.schedule(highlights.apply) end)
end

local function create_command()
  vim.api.nvim_create_user_command("Preview", function(opts)
    local sub = opts.args
    if not is_subcommand(sub) then
      log.error("command", ("unknown subcommand %q (expected toggle, preview or markdown)"):format(sub))
      return
    end
    local win = vim.api.nvim_get_current_win()
    if sub == "toggle" then
      M.toggle(win)
    else
      M.set_mode(win, sub)
    end
  end, {
    nargs = 1,
    desc = "Switch a markdown window between preview and raw markdown",
    complete = function(arglead)
      return complete_subcommand(arglead)
    end,
  })
end

-- Public API -----------------------------------------------------------------

---@param opts table|nil
function M.setup(opts)
  local resolved, err = config.resolve(opts)
  if resolved == nil then
    log.error("setup", err or "invalid configuration")
    return
  end
  cfg = resolved
  winbar.configure(cfg.winbar)
  render.configure(cfg)
  highlights.configure(cfg.highlights)
  highlights.apply()
  create_autocmds()
  create_command()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    sync_window(win)
  end
end

--- Deep copy of the resolved configuration, or nil before setup.
---@return preview.Config|nil
function M.config()
  return cfg and vim.deepcopy(cfg) or nil
end

--- Switches a managed window's mode. No-op for unmanaged or closed windows
--- and when the mode is unchanged. Entering preview saves the window options
--- it touches and applies the reading view; leaving restores them. The renderer
--- attaches on the buffer's first preview window and detaches when the last
--- one leaves.
---@param win integer
---@param mode preview.Mode
function M.set_mode(win, mode)
  if cfg == nil or not vim.api.nvim_win_is_valid(win) or state.mode(win) == mode then
    return
  end
  local entry = state.get_window(win)
  if not entry or entry.buf ~= vim.api.nvim_win_get_buf(win) then
    return
  end
  if mode == "preview" and not entry.suspended then
    entry.saved_options = snapshot_options(win, saved_keys())
  elseif mode == "markdown" then
    apply_options(win, restorable(entry.saved_options))
    render.release(win)
  end
  entry.mode = mode
  apply_entry(win, entry)
  redraw(win)
end

--- Flips the mode of `win` (default: current window). No-op when unmanaged.
---@param win integer|nil
function M.toggle(win)
  win = win or vim.api.nvim_get_current_win()
  local current = state.mode(win)
  if current ~= nil then
    M.set_mode(win, other_mode(current))
  end
end

--- Mode of `win` (default: current window), or nil when unmanaged.
---@param win integer|nil
---@return preview.Mode|nil
function M.mode(win)
  return state.mode(win or vim.api.nvim_get_current_win())
end

return M
