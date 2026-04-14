-- tiny-jump.nvim — a fork of https://github.com/yorickpeterse/nvim-jump
-- Original work: Copyright (c) Yorick Peterse
-- Modifications: Copyright (c) 2026 Stephen Waits
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local api = vim.api
local fn = vim.fn
local M = {}

M.config = {
  -- The labels that may be used, in order of their preference. Ordered by
  -- QWERTY finger strength (index > middle > ring > pinky, home > top >
  -- bottom) with hand alternation to break ties.
  labels = 'fjdkslahgeiruowmcnvptyqxzb',

  -- The highlight group to use for match highlights.
  search = 'Search',

  -- The highlight group to use for labels. May be a group name (string) or
  -- a table of `nvim_set_hl` attributes.
  label = 'IncSearch',
}

local K = {
  CR = vim.keycode('<cr>'),
  BS = vim.keycode('<bs>'),
  C_H = vim.keycode('<c-h>'),
  ESC = vim.keycode('<esc>'),
}
local NS = api.nvim_create_namespace('tiny-jump')

-- Find all matches of `pattern` in `lines` and compute the set of labels that
-- do not conflict with the character immediately following any match (so that
-- typing the next input character cannot be mistaken for a label).
local function scan(pattern, lines, start_line)
  local lower = pattern == pattern:lower()
  local matches, avail = {}, {}
  for i = 1, #M.config.labels do
    avail[M.config.labels:sub(i, i)] = true
  end
  for idx, line in ipairs(lines) do
    local search_line = lower and line:lower() or line
    local col = 1
    while true do
      local s, e = search_line:find(pattern, col, true)
      if not s then
        break
      end
      col = e + 1
      matches[#matches + 1] = {
        line = start_line + idx - 2,
        start_col = s - 1,
        end_col = e,
      }
      avail[line:sub(e + 1, e + 1):lower()] = false
    end
  end
  return matches, avail
end

function M.start()
  local win = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  local info = fn.getwininfo(win)[1]
  local top = info.topline
  local lines = api.nvim_buf_get_lines(buf, top - 1, info.botline, true)
  local chars, active = '', {}

  while true do
    api.nvim_echo({ { '/' .. chars, '' } }, false, {})
    local ch = fn.getcharstr(-1)
    local jump_to = active[ch]

    if ch == K.ESC then
      break
    elseif ch == K.CR then
      for i = 1, #M.config.labels do
        local c = M.config.labels:sub(i, i)
        if active[c] then
          jump_to = active[c]
          break
        end
      end
      if jump_to then
        api.nvim_win_set_cursor(win, jump_to)
      end
      break
    elseif ch == K.BS or ch == K.C_H then
      chars = chars:sub(1, -2)
    elseif jump_to then
      api.nvim_win_set_cursor(win, jump_to)
      break
    else
      chars = chars .. ch
    end

    active = {}
    api.nvim_buf_clear_namespace(buf, NS, 0, -1)

    if #chars > 0 then
      local matches, avail = scan(chars, lines, top)
      local cr = api.nvim_win_get_cursor(win)
      local cl, cc = cr[1] - 1, cr[2]
      table.sort(matches, function(a, b)
        local da, db = math.abs(a.line - cl), math.abs(b.line - cl)
        if da ~= db then
          return da < db
        end
        return math.abs(a.start_col - cc) < math.abs(b.start_col - cc)
      end)
      local li = 1
      for _, m in ipairs(matches) do
        vim.hl.range(
          buf,
          NS,
          M.config.search,
          { m.line, m.start_col },
          { m.line, m.end_col },
          { priority = 200 }
        )
        while
          li <= #M.config.labels and not avail[M.config.labels:sub(li, li)]
        do
          li = li + 1
        end
        if li <= #M.config.labels then
          local label = M.config.labels:sub(li, li)
          li = li + 1
          active[label] = { m.line + 1, m.start_col }
          api.nvim_buf_set_extmark(buf, NS, m.line, m.start_col, {
            virt_text = { { label, M.config.label } },
            virt_text_pos = 'overlay',
            priority = 201,
          })
        end
      end
    end

    vim.cmd.redraw()
  end

  api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  api.nvim_echo({ { '', '' } }, false, {})
  vim.cmd.redraw()
end

function M.setup(opts)
  M.config = vim.tbl_extend('force', M.config, opts or {})
  local group =
    api.nvim_create_augroup('tiny-jump.highlights', { clear = true })
  if type(M.config.label) == 'table' then
    local attrs = M.config.label
    M.config.label = 'TinyJumpLabel'
    -- Apply now (setup may run after the colorscheme is already loaded) and
    -- on every ColorScheme event (themes clear user-defined highlights).
    local function apply()
      api.nvim_set_hl(0, 'TinyJumpLabel', attrs)
    end
    apply()
    api.nvim_create_autocmd('ColorScheme', { group = group, callback = apply })
  end
end

return M
