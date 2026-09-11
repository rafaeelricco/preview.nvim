--- Registry of render elements. Adding an element is one file plus one line here.
---@type preview.Element[]
return {
  require("preview.render.heading"),
  require("preview.render.code"),
  require("preview.render.code_span"),
  require("preview.render.quote"),
  require("preview.render.list"),
  require("preview.render.rule"),
  require("preview.render.emphasis"),
  require("preview.render.link"),
  require("preview.render.table"),
}
