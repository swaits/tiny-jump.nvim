-- tiny-jump.nvim — a fork of https://github.com/yorickpeterse/nvim-jump
-- Original work: Copyright (c) Yorick Peterse
-- Modifications: Copyright (c) 2026 Stephen Waits
--
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local api, fn, M = vim.api, vim.fn, {}

M.config = {
  labels = 'fjdkslahgeiruowmcnvptyqxzb',
  search = 'Search',
  label = 'IncSearch',
}

-- Termcode constants. BS and C_H cover both backspace variants terminals send.
local K = { CR = vim.keycode('<cr>'), BS = vim.keycode('<bs>'), C_H = vim.keycode('<c-h>'), ESC = vim.keycode('<esc>') }
local NS = api.nvim_create_namespace('tiny-jump')

-- Scan the visible lines for matches of `pattern` and, as a side product,
-- compute `avail[c]` = true for each label char `c` that is *safe* to use as a
-- label — i.e. `c` is never the character immediately following a match. If it
-- were, pressing `c` would be ambiguous: jump-to-label-c vs extend-pattern-by-c.
local function scan(pattern, lines, start_line)
  -- smartcase: lowercase-only pattern → case-insensitive search
  local lower = pattern == pattern:lower()
  local matches, avail = {}, {}
  for i = 1, #M.config.labels do
    avail[M.config.labels:sub(i, i)] = true
  end
  for idx, line in ipairs(lines) do
    local sline = lower and line:lower() or line
    local col = 1
    while true do
      local s, e = sline:find(pattern, col, true)
      if not s then break end
      col = e + 1
      -- start_line is 1-indexed (Vim convention), buffer rows are 0-indexed, and
      -- ipairs's idx is also 1-indexed — the `- 2` reconciles both offsets.
      matches[#matches + 1] = { line = start_line + idx - 2, start_col = s - 1, end_col = e }
      -- Mark the char after this match as unavailable for labeling. Note this
      -- is a *global* disqualification: any one match with 'e' next disables
      -- the 'e' label for all matches.
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
  -- State that persists across input keystrokes:
  --   chars    = accumulated search pattern typed so far
  --   active   = map from label-key (1 or 2 chars) to { row, col } target
  --   prefixes = set of chars that are the first char of some 2-char label;
  --              input loop checks this to decide whether to buffer a 2nd key
  local chars, active, prefixes = '', {}, {}

  while true do
    api.nvim_echo({ { '/' .. chars, '' } }, false, {})
    local ch = fn.getcharstr(-1)
    -- Two-char label mode: if `ch` is a known prefix, wait for a 2nd keystroke
    -- and treat the pair as the label key.
    if prefixes[ch] then ch = ch .. fn.getcharstr(-1) end
    local jump_to = active[ch]

    if ch == K.ESC then
      break
    elseif ch == K.CR then
      -- <CR> jumps to whichever labeled match has the strongest label — i.e.
      -- the one that appears earliest in the label-preference string.
      for i = 1, #M.config.labels do
        jump_to = active[M.config.labels:sub(i, i)]
        if jump_to then break end
      end
      if jump_to then api.nvim_win_set_cursor(win, jump_to) end
      break
    elseif ch == K.BS or ch == K.C_H then
      chars = chars:sub(1, -2)
    elseif jump_to then
      api.nvim_win_set_cursor(win, jump_to)
      break
    else
      chars = chars .. ch
    end

    -- Fresh scan per keystroke: clear everything that was drawn, then redraw
    -- from the new `chars` value. `active` and `prefixes` must be regenerated
    -- because label-to-position mapping depends on the current match set.
    active, prefixes = {}, {}
    api.nvim_buf_clear_namespace(buf, NS, 0, -1)

    if #chars > 0 then
      local matches, avail = scan(chars, lines, top)
      -- Sort matches by cursor proximity so the N closest get the N strongest
      -- labels. Primary: line distance. Secondary: column distance.
      local cr = api.nvim_win_get_cursor(win)
      local cl, cc = cr[1] - 1, cr[2]
      table.sort(matches, function(a, b)
        local da, db = math.abs(a.line - cl), math.abs(b.line - cl)
        if da ~= db then return da < db end
        return math.abs(a.start_col - cc) < math.abs(b.start_col - cc)
      end)
      local L = M.config.labels
      -- Switch to two-char labels when there are more matches than single-char
      -- labels. Pair labels expand capacity to up to |L|^2 (676 with defaults),
      -- at the cost of requiring two keystrokes per jump while `two` is true.
      local two, ivs_by_line, li = #matches > #L, {}, 1
      for _, m in ipairs(matches) do
        vim.hl.range(buf, NS, M.config.search, { m.line, m.start_col }, { m.line, m.end_col }, { priority = 200 })
        local label
        if two and li <= #L * #L then
          -- Pair encoding: `a` (slow-varying) is the first char, `b` (fast-
          -- varying) is the second. So labels li=1..#L all share the same
          -- first char, keeping `prefixes` minimal for as long as possible —
          -- important because every char in `prefixes` is a char the user
          -- can no longer use to extend the search pattern in one keystroke.
          local a, b = math.floor((li - 1) / #L) + 1, (li - 1) % #L + 1
          label = L:sub(a, a) .. L:sub(b, b)
        elseif not two then
          -- Single-char: walk the cursor past any label that's unavailable
          -- (would conflict with pattern extension).
          while li <= #L and not avail[L:sub(li, li)] do
            li = li + 1
          end
          if li <= #L then label = L:sub(li, li) end
        end
        if label then
          -- Skip this match's label if it would visually overlap (or, in 2-char
          -- mode, touch within 1 column of) any label already placed on this
          -- line. The match still gets a search highlight; the unused label
          -- carries over to the next non-conflicting match.
          local gap = two and 1 or 0
          local ivs = ivs_by_line[m.line] or {}
          local fits = true
          for _, iv in ipairs(ivs) do
            -- Standard [a, b) interval-overlap test with `gap` padding on each side.
            if m.start_col < iv[2] + gap and iv[1] < m.start_col + #label + gap then
              fits = false
              break
            end
          end
          if fits then
            -- Record the 2-char label's first char so the input loop knows
            -- to buffer a second keystroke when it sees that char.
            if two then prefixes[label:sub(1, 1)] = true end
            active[label] = { m.line + 1, m.start_col }
            api.nvim_buf_set_extmark(buf, NS, m.line, m.start_col, {
              virt_text = { { label, M.config.label } },
              virt_text_pos = 'overlay',
              priority = 201,
            })
            ivs[#ivs + 1] = { m.start_col, m.start_col + #label }
            ivs_by_line[m.line] = ivs
            li = li + 1
          end
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
  -- Recreate the augroup on every setup() call (clear = true drops any prior
  -- autocmds). Without this, repeated setup calls with different label configs
  -- would accumulate stale ColorScheme autocmds.
  local group = api.nvim_create_augroup('tiny-jump.highlights', { clear = true })
  if type(M.config.label) == 'table' then
    -- User passed highlight attrs directly. Own a dedicated highlight group
    -- (TinyJumpLabel) and re-apply it on ColorScheme so their colors survive
    -- theme changes — colorschemes clear user-defined highlights.
    local attrs = M.config.label
    M.config.label = 'TinyJumpLabel'
    api.nvim_set_hl(0, 'TinyJumpLabel', attrs)
    api.nvim_create_autocmd('ColorScheme', {
      group = group,
      callback = function() api.nvim_set_hl(0, 'TinyJumpLabel', attrs) end,
    })
  end
end

return M
