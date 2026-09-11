---@diagnostic disable: duplicate-set-field
local h = require("tests.helpers")

describe("render.collect", function()
  local render = require("preview.render")
  local log = require("preview.log")
  local original_warn = log.warn_once
  local warnings

  before_each(function()
    warnings = {}
    log.warn_once = function(scope, msg)
      warnings[#warnings + 1] = { scope = scope, msg = msg }
    end
  end)
  after_each(function()
    log.warn_once = original_warn
    h.wipe()
  end)

  local function fake_match()
    return { root = {}, captures = { root = {} } }
  end

  it("groups marks by row across elements", function()
    local _, ctx = h.buffer_with({ "a", "b" })
    local one = {
      name = "collect_spec_one",
      lang = "markdown",
      query = "",
      render = function()
        return { { row = 0, col = 0, opts = {} }, { row = 1, col = 0, opts = {} } }
      end,
    }
    local two = {
      name = "collect_spec_two",
      lang = "markdown",
      query = "",
      render = function()
        return { { row = 1, col = 1, opts = {} } }
      end,
    }
    local by_row = render.collect(ctx, { one, two }, {
      collect_spec_one = { fake_match() },
      collect_spec_two = { fake_match() },
    })
    assert.equals(1, #by_row[0])
    assert.equals(2, #by_row[1])
    assert.are.same({ row = 1, col = 1, opts = {} }, by_row[1][2])
  end)

  it("skips a throwing element and warns exactly once across two calls", function()
    local _, ctx = h.buffer_with({ "a" })
    local broken = {
      name = "collect_spec_broken",
      lang = "markdown",
      query = "",
      render = function()
        error("boom")
      end,
    }
    local fine = {
      name = "collect_spec_fine",
      lang = "markdown",
      query = "",
      render = function()
        return { { row = 0, col = 0, opts = {} } }
      end,
    }
    local matches = { collect_spec_broken = { fake_match(), fake_match() }, collect_spec_fine = { fake_match() } }

    local first = render.collect(ctx, { broken, fine }, matches)
    local second = render.collect(ctx, { broken, fine }, matches)

    assert.equals(1, #first[0])
    assert.equals(1, #second[0])
    assert.equals(1, #warnings)
    assert.equals("render", warnings[1].scope)
    assert.is_truthy(warnings[1].msg:find("collect_spec_broken", 1, true))
    assert.is_truthy(warnings[1].msg:find("boom", 1, true))
  end)

  it("merges stronger row flows and discards partial flows from a failed element", function()
    local _, ctx = h.buffer_with({ "a" })
    local function element(name, kind)
      return { name=name, lang="markdown", query="", render=function()
        return {}, {{row=0,kind=kind,indent=3}}
      end }
    end
    local list, code, tbl = element("flow_list", "list"), element("flow_code", "code"), element("flow_table", "table")
    local broken = element("flow_broken", "table")
    local calls = 0
    broken.render = function()
      calls = calls + 1
      if calls == 2 then error("invalid second match") end
      return {}, {{row=0,kind="table",indent=99}}
    end
    local _, flows = render.collect(ctx, {list, code, tbl, broken}, {
      flow_list={fake_match()}, flow_code={fake_match()}, flow_table={fake_match()},
      flow_broken={fake_match(),fake_match()},
    })
    assert.equals("table", flows[0].kind)
    assert.equals(3, flows[0].indent)
  end)
end)
