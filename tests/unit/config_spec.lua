local config = require("preview.config")

--- Whether `s` is a string that contains `needle` as plain text. Pure.
---@param s any
---@param needle string
---@return boolean
local function contains(s, needle)
  return type(s) == "string" and s:find(needle, 1, true) ~= nil
end

describe("preview.config", function()
  local original_notify_once = vim.notify_once
  local notify_calls

  before_each(function()
    notify_calls = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify_once = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify_once = original_notify_once
  end)

  it("resolves defaults when called with nil", function()
    local cfg, err = config.resolve(nil)
    assert.is_nil(err)
    assert.are.same(config.defaults, cfg)
  end)

  it("resolves defaults when called with an empty table", function()
    local cfg, err = config.resolve({})
    assert.is_nil(err)
    assert.are.same(config.defaults, cfg)
  end)

  it("does not share tables with defaults", function()
    local cfg = config.resolve({}) --[[@as preview.Config]]
    cfg.render.quote.bar = "changed"
    assert.equals("▎", config.defaults.render.quote.bar)
  end)

  it("reports a wrong type with the dotted key path", function()
    local cfg, err = config.resolve({ winbar = { enabled = 42 } })
    assert.is_nil(cfg)
    assert.is_string(err)
    assert.is_true(contains(err, "winbar.enabled"))
  end)

  it("reports an out-of-set value with the dotted key path", function()
    local cfg, err = config.resolve({ default_mode = "raw" })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "default_mode"))
  end)

  it("warns exactly once for an unknown key", function()
    local cfg, err = config.resolve({ nonsense = 1 })
    assert.is_nil(err)
    assert.is_table(cfg)
    assert.equals(1, #notify_calls)
    assert.is_true(contains(notify_calls[1] and notify_calls[1].msg, "nonsense"))
    assert.equals(vim.log.levels.WARN, notify_calls[1].level)
  end)

  it("names nested unknown keys with the dotted path", function()
    config.resolve({ render = { heading = { colour = true } } })
    assert.equals(1, #notify_calls)
    assert.is_true(contains(notify_calls[1] and notify_calls[1].msg, "render.heading.colour"))
  end)

  it("does not warn for known keys", function()
    config.resolve({ render = { heading = { icons = { "1", "2", "3", "4", "5", "6" } } } })
    assert.equals(0, #notify_calls)
  end)

  it("resolves twice to deep-equal tables", function()
    local user = { winbar = { enabled = false }, render = { quote = { bar = "|" } } }
    local first = config.resolve(user)
    local second = config.resolve(user)
    assert.are.same(first, second)
  end)

  it("accepts keymap = false", function()
    local cfg, err = config.resolve({ keymap = false })
    assert.is_nil(err)
    assert.equals(false, cfg and cfg.keymap)
  end)

  it("rejects keymap of a non-string, non-false type", function()
    local cfg, err = config.resolve({ keymap = 3 })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "keymap"))
  end)

  it("accepts code.label = false", function()
    local cfg, err = config.resolve({ render = { code = { label = false } } })
    assert.is_nil(err)
    assert.equals(false, cfg and cfg.render.code.label)
  end)

  it("rejects code.label outside left/right/false", function()
    local cfg, err = config.resolve({ render = { code = { label = "top" } } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "render.code.label"))
  end)

  it("rejects heading.icons with 5 entries", function()
    local cfg, err = config.resolve({ render = { heading = { icons = { "a", "b", "c", "d", "e" } } } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "render.heading.icons"))
  end)

  it("rejects heading.bold with 5 entries", function()
    local cfg, err = config.resolve({ render = { heading = { bold = { true, true, true, true, true } } } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "render.heading.bold"))
  end)

  it("rejects an empty list.bullets", function()
    local cfg, err = config.resolve({ render = { list = { bullets = {} } } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "render.list.bullets"))
  end)

  it("resolves the reading-view defaults", function()
    local cfg = config.resolve({}) --[[@as preview.Config]]
    assert.are.same({ gutter = 2, max_width = 0, center = true }, cfg.view)
    assert.are.same({ "", "", "", "", "", "" }, cfg.render.heading.icons)
    assert.are.same({ true, true, true, false, false, false }, cfg.render.heading.bold)
    assert.are.same({ above = { 3, 2, 2, 1, 1, 1 }, below = { 1, 1, 1, 1, 1, 1 } }, cfg.render.spacing.heading)
    assert.are.same({ above = 1, below = 1 }, cfg.render.spacing.paragraph)
    assert.are.same({ above = 1, below = 1 }, cfg.render.spacing.list)
    assert.are.same({ above = 1, below = 1 }, cfg.render.spacing.quote)
    assert.are.same({ above = 1, below = 1 }, cfg.render.spacing.code)
    assert.are.same({ above = 1, below = 1 }, cfg.render.spacing.table)
    assert.are.same({ above = 1, below = 1 }, cfg.render.spacing.rule)
    assert.are.same({ "•", "◦", "▪", "▫" }, cfg.render.list.bullets)
    assert.equals(1, cfg.render.list.gap)
    assert.equals(1, cfg.render.checkbox.gap)
    assert.equals(false, cfg.render.code.label)
    assert.equals(2, cfg.render.code.padding)
    assert.equals("", cfg.render.link.icon)
    assert.equals(1, cfg.render.link.gap)
    assert.equals(true, cfg.render.table.row_lines)
  end)

  it("rejects view.gutter above 9 with the dotted key", function()
    local cfg, err = config.resolve({ view = { gutter = 10 } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "view.gutter"))
  end)

  it("rejects a fractional view.gutter with the dotted key", function()
    local cfg, err = config.resolve({ view = { gutter = 2.5 } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "view.gutter"))
  end)

  it("rejects a non-table highlight override with the dotted key", function()
    local cfg, err = config.resolve({ highlights = { PreviewLink = "Title" } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "highlights.PreviewLink"))
  end)

  it("accepts highlight overrides as full specs", function()
    local cfg, err = config.resolve({ highlights = { PreviewLink = { fg = "#ff0000" } } })
    assert.is_nil(err)
    assert.equals("#ff0000", cfg and cfg.highlights.PreviewLink.fg)
    assert.equals(0, #notify_calls)
  end)

  it("accepts view.gutter at the bounds", function()
    for _, gutter in ipairs({ 0, 9 }) do
      local cfg, err = config.resolve({ view = { gutter = gutter } })
      assert.is_nil(err)
      assert.equals(gutter, cfg and cfg.view.gutter)
    end
  end)

  it("accepts an unset or boolean view.wrap without warning", function()
    for _, wrap in ipairs({ true, false }) do
      local cfg, err = config.resolve({ view = { wrap = wrap } })
      assert.is_nil(err)
      assert.equals(wrap, cfg and cfg.view.wrap)
    end
    assert.is_nil(assert(config.resolve({})).view.wrap)
    assert.equals(0, #notify_calls)
  end)

  it("rejects a non-boolean view.wrap with the dotted key", function()
    local cfg, err = config.resolve({ view = { wrap = "yes" } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "view.wrap"))
  end)

  it("rejects invalid view.max_width values with the dotted key", function()
    for _, max_width in ipairs({ -1, 2.5, "100" }) do
      local cfg, err = config.resolve({ view = { max_width = max_width } })
      assert.is_nil(cfg)
      assert.is_true(contains(err, "view.max_width"))
    end
  end)

  it("accepts zero as an uncapped view.max_width", function()
    local cfg, err = config.resolve({ view = { max_width = 0 } })
    assert.is_nil(err)
    assert.equals(0, cfg and cfg.view.max_width)
  end)

  it("rejects a non-boolean view.center with the dotted key", function()
    local cfg, err = config.resolve({ view = { center = "yes" } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "view.center"))
  end)

  it("warns that render.heading.space_above is now an unknown key", function()
    local cfg, err = config.resolve({ render = { heading = { space_above = { 1, 1, 1, 1, 1, 1 } } } })
    assert.is_nil(err)
    assert.is_table(cfg)
    assert.equals(1, #notify_calls)
    assert.is_true(contains(notify_calls[1] and notify_calls[1].msg, "render.heading.space_above"))
  end)

  it("rejects a negative render.spacing.paragraph.above with the dotted key", function()
    local cfg, err = config.resolve({ render = { spacing = { paragraph = { above = -1 } } } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "render.spacing.paragraph.above"))
  end)

  it("rejects a negative render.list.gap with the dotted key", function()
    local cfg, err = config.resolve({ render = { list = { gap = -1 } } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "render.list.gap"))
  end)

  it("rejects invalid code.padding values with the dotted key", function()
    for _, padding in ipairs({ -1, 1.5, "2" }) do
      local cfg, err = config.resolve({ render = { code = { padding = padding } } })
      assert.is_nil(cfg)
      assert.is_true(contains(err, "render.code.padding"))
    end
  end)

  it("rejects a non-boolean table.row_lines with the dotted key", function()
    local cfg, err = config.resolve({ render = { table = { row_lines = "x" } } })
    assert.is_nil(cfg)
    assert.is_true(contains(err, "render.table.row_lines"))
  end)

  it("never throws on a non-table argument", function()
    local ok, cfg, err = pcall(config.resolve, "oops")
    assert.is_true(ok)
    assert.is_nil(cfg)
    assert.is_string(err)
  end)

  it("lists unknown keys as dotted paths", function()
    local keys = config.unknown_keys(config.defaults, { foo = 1, winbar = { bar = 2 } })
    table.sort(keys)
    assert.are.same({ "foo", "winbar.bar" }, keys)
  end)
end)
