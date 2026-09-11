vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.shortmess:append("I")
vim.opt.more = false
-- Avoid runtime ftplugins (e.g. markdown treesitter) blowing up headless tests.
vim.cmd("filetype plugin indent off")

local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:prepend(plenary_path)
end

local has_plenary = pcall(require, "plenary.busted")
if has_plenary then
  -- Plenary otherwise launches its workers with the user's init.lua, even
  -- though this parent uses a minimal init. Keep the documented command isolated.
  local harness = require("plenary.test_harness")
  local test_directory = harness.test_directory
  local minimal_init = vim.fn.fnamemodify("tests/minimal_init.lua", ":p")
  harness.test_directory = function(directory, opts)
    return test_directory(directory, vim.tbl_extend("keep", opts or {}, { minimal_init = minimal_init }))
  end
  return
end

local failures = 0
local contexts = { { before = {}, after = {} } }

local function current_context()
  return contexts[#contexts]
end

local function fail(message)
  error(message, 2)
end

_G.assert = setmetatable({
  is_true = function(value)
    if value ~= true then
      fail("expected true")
    end
  end,
  is_false = function(value)
    if value ~= false then
      fail("expected false")
    end
  end,
  is_nil = function(value)
    if value ~= nil then
      fail("expected nil")
    end
  end,
  is_not_nil = function(value)
    if value == nil then
      fail("expected non-nil")
    end
  end,
  is_table = function(value)
    if type(value) ~= "table" then
      fail("expected table")
    end
  end,
  is_function = function(value)
    if type(value) ~= "function" then
      fail("expected function")
    end
  end,
  is_string = function(value)
    if type(value) ~= "string" then
      fail("expected string")
    end
  end,
  is_number = function(value)
    if type(value) ~= "number" then
      fail("expected number")
    end
  end,
  is_truthy = function(value)
    if not value then
      fail("expected truthy")
    end
  end,
  equals = function(expected, actual)
    if expected ~= actual then
      fail("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
    end
  end,
}, {
  __call = function(_, value, message)
    if not value then
      fail(message or "assertion failed")
    end
  end,
})

function _G.describe(_, fn)
  table.insert(contexts, { before = {}, after = {} })
  fn()
  table.remove(contexts)
end

function _G.before_each(fn)
  table.insert(current_context().before, fn)
end

function _G.after_each(fn)
  table.insert(current_context().after, fn)
end

local function all_hooks(kind)
  local hooks = {}
  for _, context in ipairs(contexts) do
    for _, hook in ipairs(context[kind]) do
      table.insert(hooks, hook)
    end
  end
  return hooks
end

function _G.it(name, fn)
  local ok, err = pcall(function()
    for _, hook in ipairs(all_hooks("before")) do
      hook()
    end
    fn()
  end)
  local after_ok, after_err = pcall(function()
    local after_hooks = all_hooks("after")
    for index = #after_hooks, 1, -1 do
      after_hooks[index]()
    end
  end)
  if ok and after_ok then
    print("ok - " .. name)
  else
    failures = failures + 1
    print("not ok - " .. name .. ": " .. tostring(not ok and err or after_err))
  end
end

vim.api.nvim_create_user_command("PlenaryBustedDirectory", function(opts)
  local root = vim.fn.fnamemodify(opts.args, ":p")
  local files = vim.fn.globpath(root, "**/*_spec.lua", false, true)
  table.sort(files)
  for _, file in ipairs(files) do
    dofile(file)
  end
  if failures > 0 then
    vim.cmd("cquit")
  end
end, { nargs = 1 })
