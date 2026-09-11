---@diagnostic disable: redundant-parameter
local highlights = require("preview.ui.highlights")

--- Fake resolved palette groups, every color present. Pure.
---@return preview.HighlightSources
local function full_sources()
  return {
    Normal = { fg = 0x111111, bg = 0xfafafa },
    Comment = { fg = 0x9a9a9a },
    CursorLine = { bg = 0xeeeeee },
    WinSeparator = { fg = 0xcccccc },
    DiagnosticInfo = { fg = 0x0066cc },
  }
end

--- Reads a group with links resolved so the concrete values are visible.
---@param name string
---@return vim.api.keyset.get_hl_info
local function get(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

describe("preview.ui.highlights", function()
  describe("derive", function()
    it("keeps every heading level at the text color, all bold", function()
      local groups = highlights.derive(full_sources())
      for level = 1, 6 do
        local spec = groups["PreviewH" .. level]
        assert.equals(0x111111, spec.fg, "level " .. level)
        assert.equals(true, spec.bold)
        assert.is_nil(spec.bg)
      end
    end)

    it("derives each group from the plan's source and attribute", function()
      local groups = highlights.derive(full_sources())
      assert.are.same({ fg = 0x111111, bold = true }, groups.PreviewBold)
      assert.are.same({ italic = true }, groups.PreviewItalic)
      assert.are.same({ bg = 0xeeeeee }, groups.PreviewCodeBlock)
      assert.are.same({ fg = 0x111111, bg = 0xeeeeee }, groups.PreviewCodeInline)
      assert.are.same({ fg = 0x9a9a9a, bg = 0xeeeeee }, groups.PreviewCodeLabel)
      assert.are.same({ fg = 0x111111 }, groups.PreviewBullet)
      assert.are.same({ fg = 0x0066cc }, groups.PreviewCheckbox)
      assert.are.same({ fg = 0xcccccc }, groups.PreviewQuote)
      assert.are.same({ fg = 0x0066cc, underline = true }, groups.PreviewLink)
      assert.are.same({ fg = 0xcccccc }, groups.PreviewTable)
      assert.are.same({ fg = 0x111111 }, groups.PreviewTableBody)
      assert.are.same({ fg = 0x111111, bold = true }, groups.PreviewTableHeader)
      assert.are.same({ fg = 0xcccccc }, groups.PreviewRule)
      assert.are.same({ fg = 0x9a9a9a, bg = 0xfafafa }, groups.PreviewWinbar)
      assert.are.same({ fg = 0x111111, bg = 0xeeeeee, bold = true }, groups.PreviewButtonActive)
      assert.are.same({ fg = 0x9a9a9a, bg = 0xfafafa }, groups.PreviewButtonInactive)
    end)

    it("leaves a derived color nil when the source group lacks it", function()
      local sources = full_sources()
      sources.Normal.bg = nil
      sources.CursorLine.bg = nil
      local groups = highlights.derive(sources)
      assert.is_nil(groups.PreviewWinbar.bg)
      assert.is_nil(groups.PreviewButtonInactive.bg)
      assert.is_nil(groups.PreviewButtonActive.bg)
      assert.is_nil(groups.PreviewCodeBlock.bg)
      assert.is_nil(groups.PreviewCodeInline.bg)
      assert.equals(0x111111, groups.PreviewCodeInline.fg)
    end)

    it("is pure: the same sources give equal tables and the input is untouched", function()
      local sources = full_sources()
      local first = highlights.derive(sources)
      local second = highlights.derive(sources)
      assert.are.same(first, second)
      assert.are.same(full_sources(), sources)
    end)

    it("names only Preview* groups", function()
      for group in pairs(highlights.derive(full_sources())) do
        assert.truthy(group:find("^Preview"))
      end
    end)
  end)

  describe("apply", function()
    before_each(function()
      vim.api.nvim_set_hl(0, "Normal", { fg = 0x1b1b1b, bg = 0xf5f5f5 })
      vim.api.nvim_set_hl(0, "Comment", { fg = 0x9a9a9a })
      vim.api.nvim_set_hl(0, "CursorLine", { bg = 0xe6e6e6 })
      vim.api.nvim_set_hl(0, "WinSeparator", { fg = 0xd0d0d0 })
      vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = 0x0055aa })
      vim.api.nvim_set_hl(0, "WinBar", { bg = 0x07080d })
      vim.api.nvim_set_hl(0, "WinBarNC", { bg = 0x07080d })
    end)

    it("writes concrete values, never links", function()
      highlights.apply()
      for group in pairs(highlights.derive(full_sources())) do
        assert.equals(1, vim.fn.hlexists(group))
        local linked = vim.api.nvim_get_hl(0, { name = group })
        assert.is_nil(linked.link)
      end
      assert.equals(0x1b1b1b, get("PreviewH1").fg)
      assert.equals(0xe6e6e6, get("PreviewCodeBlock").bg)
      assert.equals(0xd0d0d0, get("PreviewQuote").fg)
      assert.equals(0x0055aa, get("PreviewLink").fg)
      assert.equals(true, get("PreviewLink").underline)
    end)

    it("uses the panel surface for the active button without reversing colors", function()
      highlights.apply()
      local active = get("PreviewButtonActive")
      assert.is_nil(active.reverse)
      assert.equals(get("CursorLine").bg, active.bg)
      assert.equals(true, active.bold)
      assert.equals(get("Normal").fg, active.fg)
    end)

    it("follows Comment when applied again after a palette change", function()
      highlights.apply()
      assert.equals(0x9a9a9a, get("PreviewButtonInactive").fg)
      vim.api.nvim_set_hl(0, "Comment", { fg = 0x717171 })
      vim.api.nvim_set_hl(0, "CursorLine", { bg = 0x262626 })
      highlights.apply()
      assert.equals(0x717171, get("PreviewButtonInactive").fg)
      assert.equals(0x262626, get("PreviewButtonActive").bg)
    end)

    it("never gives the winbar the stock WinBar background", function()
      highlights.apply()
      assert.are_not.equals(0x07080d, get("PreviewWinbar").bg)
      assert.equals(0xf5f5f5, get("PreviewWinbar").bg)
    end)

    it("replaces a derived group with a configured override, whole spec", function()
      highlights.configure({ PreviewLink = { fg = 0xff0000 } })
      highlights.apply()
      local link = get("PreviewLink")
      assert.equals(0xff0000, link.fg)
      assert.is_nil(link.underline)
      highlights.configure({})
      highlights.apply()
      assert.is_false(get("PreviewLink").fg == 0xff0000)
    end)

    it("keeps the override across a palette change", function()
      highlights.configure({ PreviewButtonInactive = { fg = 0x00ff00 } })
      highlights.apply()
      vim.api.nvim_set_hl(0, "Comment", { fg = 0x123456 })
      highlights.apply()
      assert.equals(0x00ff00, get("PreviewButtonInactive").fg)
      highlights.configure({})
    end)

    it("does not error when called twice", function()
      assert.has_no.errors(function()
        highlights.apply()
        highlights.apply()
      end)
    end)
  end)
end)
