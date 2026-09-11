local M = {}

--- A real embedded Neovim UI: assertions read the composed screen, not mark specs.
---@param width integer
---@param height integer
function M.new(width, height)
  local channel = vim.fn.jobstart({ vim.v.progpath, "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
  assert(channel > 0, "could not start embedded Neovim")
  local ui = {}
  function ui.request(method, ...)
    return vim.rpcrequest(channel, method, ...)
  end
  function ui.exec(code, args)
    return ui.request("nvim_exec_lua", code, args or {})
  end
  function ui.redraw()
    ui.exec("vim.wait(10, function() return false end); vim.cmd('redraw!')")
  end
  function ui.resize(w, h)
    width, height = w, h
    ui.request("nvim_ui_try_resize", w, h)
    ui.redraw()
  end
  function ui.lines()
    ui.redraw()
    return ui.exec([[
      local width, height = ...
      local rows = {}
      for r = 1, height do
        local cells = {}
        for c = 1, width do cells[#cells + 1] = vim.fn.screenstring(r, c) end
        rows[r] = table.concat(cells):gsub('%s+$', '')
      end
      return rows
    ]], { width, height })
  end
  function ui.close()
    vim.fn.jobstop(channel)
  end
  ui.request("nvim_ui_attach", width, height, { rgb = true })
  ui.exec([[
    vim.opt.rtp:prepend(...)
    vim.o.hidden = true
    vim.o.termguicolors = true
    vim.o.laststatus = 0
    vim.o.showmode = false
    vim.o.ruler = false
    vim.o.more = false
    _G.notifications = {}
    vim.notify = function(message, level)
      _G.notifications[#_G.notifications + 1] = {message=message, level=level}
    end
    vim.cmd('filetype plugin indent on')
  ]], { vim.fn.getcwd() })
  return ui
end

return M
