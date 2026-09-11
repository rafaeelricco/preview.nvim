---@diagnostic disable: duplicate-set-field
local h = require("tests.helpers")

describe("render.query", function()
  local query = require("preview.render.query")
  local render = require("preview.render")
  local log = require("preview.log")
  local original_warn = log.warn_once
  local original_get_parser = vim.treesitter.get_parser
  local warnings

  before_each(function()
    warnings = {}
    log.warn_once = function(scope, msg)
      warnings[#warnings + 1] = { scope = scope, msg = msg }
    end
  end)
  after_each(function()
    log.warn_once = original_warn
    vim.treesitter.get_parser = original_get_parser
    h.wipe()
  end)

  it("keys matches by element name with @root always present", function()
    local buf, ctx = h.buffer_with({ "# Title", "", "Some *text*." })
    local matches = query.matches(buf, render.elements(), ctx.top, ctx.bot)
    assert.equals(1, #matches.heading)
    assert.equals("atx_heading", matches.heading[1].root:type())
    assert.equals("atx_h1_marker", matches.heading[1].captures.marker[1]:type())
    assert.equals(1, #matches.emphasis)
    assert.equals("emphasis", matches.emphasis[1].captures.root[1]:type())
  end)

  it("restricts matches to the requested rows", function()
    local buf = h.buffer_with({ "# One", "# Two", "# Three" })
    local matches = query.matches(buf, render.elements(), 1, 1)
    assert.equals(1, #matches.heading)
    assert.equals(1, matches.heading[1].root:start())
  end)

  it("returns {} and warns once when there is no parser", function()
    local buf, ctx = h.buffer_with({ "# Title" })
    vim.treesitter.get_parser = function()
      return nil, "no parser"
    end
    assert.are.same({}, query.matches(buf, render.elements(), ctx.top, ctx.bot))
    assert.are.same({}, query.matches(buf, render.elements(), ctx.top, ctx.bot))
    assert.equals(1, #warnings)
    assert.equals("render", warnings[1].scope)
  end)

  it("returns {} when parse yields nil", function()
    local buf, ctx = h.buffer_with({ "# Title" })
    vim.treesitter.get_parser = function()
      return {
        parse = function()
          return nil
        end,
      }
    end
    assert.are.same({}, query.matches(buf, render.elements(), ctx.top, ctx.bot))
  end)

  it("compiles each element query once", function()
    local element = render.elements()[1]
    assert.equals(query.for_element(element), query.for_element(element))
  end)
end)
