# tiny-jump.nvim

A tiny, no-nonsense jump plugin for Neovim. Press a key to trigger, type
one or more characters to narrow the matches, then press the label to
jump. Like `/` but you don't have to `n` your way to the match you
actually wanted.

## Credit and history

This plugin is a fork of
[yorickpeterse/nvim-jump](https://github.com/yorickpeterse/nvim-jump),
which is excellent and which I used happily for a long time. Big thanks
to the original author for a clean, focused implementation.

I forked it because I wanted to pass label highlight attributes directly
to `setup()` (instead of having to define a separate highlight group and
re-apply it on every colorscheme change). I submitted that as a PR but
it was declined, which is the maintainer's right — the upstream plugin
is explicitly considered feature-complete. See the closed PR for
context: <https://github.com/yorickpeterse/nvim-jump/pull/8>.

Since the upstream code is MPL-2.0, a fork is fair game. This plugin is
a tiny extension of it — same core behavior, plus a slightly friendlier
highlight API — maintained under the `tiny-*` family of my other
Neovim plugins.

## Requirements

- Neovim 0.11.0 or newer.

## Install & basic usage

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ 'https://github.com/swaits/tiny-jump.nvim' })

vim.keymap.set({ 'n', 'x', 'o' }, 's', require('tiny-jump').start)
```

Any plugin manager works — just point it at this repo and map
`require('tiny-jump').start` to a key.

## Configuration

All settings are optional. Defaults:

```lua
require('tiny-jump').setup({
  -- Labels that may be used, in order of preference.
  labels = 'fdsaghjklrewqtyuiopvcxzbnm',

  -- Highlight group used for match highlights (before labels are shown).
  search = 'Search',

  -- Highlight for labels. Accepts a group name (string) or a table of
  -- `nvim_set_hl` attributes.
  label = 'IncSearch',
})
```

### Label colors

Point `label` at any existing highlight group:

```lua
require('tiny-jump').setup({ label = 'IncSearch' })
```

Or pass attributes inline and let the plugin manage the group for you.
It creates an internal `TinyJumpLabel` group and re-applies it on
`ColorScheme` so your colors survive theme changes:

```lua
require('tiny-jump').setup({
  label = { fg = '#ffff00', bg = '#000000', bold = true },
})
```

### Colemak

```lua
require('tiny-jump').setup({
  labels = 'tnseriaogmplfuwyqbjdhvkzxc',
})
```

## License

MPL-2.0, inherited from the upstream project. See `LICENSE`.
