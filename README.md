                                              __
                                             / /_  ____  ____
                                            / __ \/ __ \/ __ \
                                           / / / / /_/ / /_/ /
                                          /_/ /_/\____/ .___/
                                                     /_/
                                      · Neovim motions on speed! ·

[![](https://img.shields.io/badge/matrix-join%20the%20speed!-blueviolet)](https://matrix.to/#/#hop.nvim:matrix.org)

**Hop** is an [EasyMotion]-like plugin allowing you to jump anywhere in a
document with as few keystrokes as possible. It does so by annotating text in
your buffer with hints, short string sequences for which each character
represents a key to type to jump to the annotated text. Most of the time,
those sequences’ lengths will be between 1 to 3 characters, making every jump
target in your document reachable in a few keystrokes.

**Hop** is a complete from-scratch rewrite of [EasyMotion], a famous plugin to
enhance the native motions of Vim. Even though [EasyMotion] is usable in
Neovim, it suffers from a few drawbacks making it not comfortable to use with
Neovim version >0.5 – at least at the time of writing these lines:

- [EasyMotion] uses an old trick to annotate jump targets by saving the
  contents of the buffer, replacing it with the highlighted annotations and
  then restoring the initial buffer after jump. This trick is dangerous as it
  will change the contents of your buffer. A UI plugin should never do anything
  to existing buffers’ contents.
- Because the contents of buffers will temporarily change, other parts of the
  editor and/or plugins relying on buffer change events will react and will go
  mad. An example is the internal LSP client implementation of Neovim >0.5 or
  its treesitter native implementation. For LSP, it means that the connected
  LSP server will receive a buffer with the jump target annotations… not
  ideal.

**Hop** is a modern take implementing this concept for the latest versions of
Neovim.

<!-- vim-markdown-toc GFM -->

* [Features](#features)
  * [Word mode (`:HopWord`)](#word-mode-hopword)
  * [Line mode (`:HopLine`)](#line-mode-hopline)
  * [1-char mode (`:HopChar1`)](#1-char-mode-hopchar1)
  * [2-char mode (`:HopChar2`)](#2-char-mode-hopchar2)
  * [Pattern mode (`:HopPattern`)](#pattern-mode-hoppattern)
  * [Visual extend](#visual-extend)
  * [Jump on sole occurrence](#jump-on-sole-occurrence)
  * [Use as operator motion](#use-as-operator-motion)
* [Getting started](#getting-started)
  * [Installation](#installation)
    * [Using [vim-plug]](#using-vim-plug)
    * [Using [packer]](#using-packer)
    * [Special notes regarding extended marks and virtual text](#special-notes-regarding-extended-marks-and-virtual-text)
* [Usage](#usage)
* [Keybindings](#keybindings)
* [Configuration](#configuration)
* [Chat](#chat)

<!-- vim-markdown-toc -->

# Features

- [x] Go to any word in the current buffer.
- [x] Go to any character in the current buffer.
- [x] Go to any bigrams in the current buffer.
- [x] Make an arbitrary search akin to <kbd>/</kbd> and go to any occurrences.
- [x] Go to any line.
- [x] Visual extend mode, which allows you to extend a visual selection by hopping elsewhere in the document.
- [x] Use it with commands like `d`, `c`, `y` to delete/change/yank up to your new cursor position.

## Word mode (`:HopWord`)

This mode highlights all the recognized words in the visible part of the buffer and allows you to jump to any.

![](https://phaazon.net/media/uploads/hop_word_mode.gif)

## Line mode (`:HopLine`)

This mode highlights the beginnings of each line in the visible part of the buffer for quick line hopping.

![](https://phaazon.net/media/uploads/hop_line_mode.gif)

## 1-char mode (`:HopChar1`)

This mode expects the user to type a single character. That character will then be highlighted in the visible part of
the buffer, allowing to jump to any of its occurrence. This mode is especially useful to jump to operators, punctuations
or any symbols not recognized as parts of words.

![](https://phaazon.net/media/uploads/hop_char1_mode.gif)

## 2-char mode (`:HopChar2`)

A variant of the 1-char mode, this mode exacts the user to type two characters, representing a _bigram_ (they follow
each other, in order). The bigram occurrences in the visible part of the buffer will then be highlighted for you to jump
to any.

![](https://phaazon.net/media/uploads/hop_char2_mode.gif)

## Pattern mode (`:HopPattern`)

Akin to `/`, this mode prompts you for a pattern (regex) to search. Occurrences will be highlighted, allowing you to
jump to any.

![](https://phaazon.net/media/uploads/hop_pattern_mode.gif)

## Visual extend

If you call any Hop commands / Lua functions from one of the visual modes, the visual selection will be extended.

![](https://phaazon.net/media/uploads/hop_visual_extend.gif)

## Jump on sole occurrence

If only a single occurrence is visible in the buffer, Hop will automatically jump to it without requiring pressing any
extra key.

![](https://phaazon.net/media/uploads/hop_sole_occurrence.gif)

## Use as operator motion

You can use Hop with any command that expects a motion, such as `d`, `y`, `c`, and it does what you would expect:
Delete/yank/change the document up to the new cursor position.

<!-- TODO: image -->

# Getting started

This section will guide you through the list of steps you must take to be able to get started with **Hop**.

This plugin was written against Neovim 0.5, which is currently a nightly version. This plugin will not work:

- With a version of Neovim before 0.5.
- On Vim. **No support for Vim is planned.**

## Installation

Whatever solution / package manager you are using, you need to ensure that the `setup` Lua function is called at some
point, otherwise the plugin will not work. If your package manager doesn’t support automatic calling of this function,
you can call it manually after your plugin is installed:

```lua
require'hop'.setup()
```

To get a default experience. Feel free to customize later the `setup` invocation (`:h hop.setup`).

### Using [vim-plug]

```vim
Plug 'phaazon/hop.nvim'
```

### Using [packer]

```lua
use {
  'phaazon/hop.nvim',
  as = 'hop',
  config = function()
    -- you can configure Hop the way you like here; see :h hop-config
    require'hop'.setup { keys = 'etovxqpdygfblzhckisuran' }
  end
}
```

### Special notes regarding extended marks and virtual text

Extended marks and virtual text is a very recent addition to Neovim-0.5. The feature is still experimental but so far no
bug related to them were found in Hop. However, if you would rather stick to the legacy implementation, you are advised
to pinpoint the `pre-extmarks` branch. For instance, with [vim-plug]:

```vim
Plug 'phaazon/hop.nvim', { 'branch': 'pre-extmarks' }
```

Keep in mind that this branch is provided as-is until Neovim bugs are fixed regarding extended marks (if any). I don’t
plan on maintaining this branch and it should be short-living.

# Usage

A bunch of vim commands are available to get your fingers wrapped around **Hop** quickly:

- `:HopWord`: hop around by highlighting words.
- `:HopPattern`: hop around by matching against a pattern (as with `/`).
- `:HopChar1`: type a single key and hop to any occurrence of that key in the document.
- `:HopChar2`: type a bigram (two keys) and hop to any occurrence of that bigram in the document.
- `:HopLine`: jump to any visible line in your buffer.

If you would rather use the Lua API, you can test it via the command prompt:

```vim
:lua require'hop'.hint_words()
```

# Keybindings

Hop doesn’t set any keybindings; you will have to define them by yourself.

If you want to create a key binding (<kbd>$</kbd> in this example) from within Lua:

```lua
-- place this in one of your configuration file(s)
vim.api.nvim_set_keymap('n', '$', "<cmd>lua require'hop'.hint_words()<cr>", {})
```

For a more complete user guide and help pages:

```vim
:help hop
```

# Configuration

You can configure Hop via several different mechanisms:

- _Global configuration_ uses the Lua `setup` API (`:h hop.setup`). This allows you to setup global options that will be
  used by all Hop Lua functions as well as the vim commands (e.g. `:HopWord`). This is the easiest way to configure Hop
  on a global scale. You can do this in your `init.lua` or any `.vim` file by using the `lua` vim command.
  Example:
  ```vim
  " init.vim
  "
  " Use better keys for the bépo keyboard layout and set
  " a balanced distribution of terminal / sequence keys
  lua require'hop'.setup { keys = 'etovxqpdygfblzhckisuran', term_seq_bias = 0.5 }
  ```
- _Local configuration overrides_ are available only on the Lua API and are `{opts}` Lua tables passed to the various
  Lua functions. Those options have precedence over global options, so they allow to locally override options. Useful if
  you want to test a special option for a single Lua function, such as `require'hop'.hint_lines()`. You can test them
  inside the command line, such as:
  ```
  :lua require'hop'.hint_words({ term_seq_bias = 0.5 })
  ```
- In the case of none of the above are provided, options are automatically read from the _default_ options. See `:h
  hop-config` for a list of default values.

# Chat

Join the discussion on the official [Matrix room](https://matrix.to/#/#hop.nvim:matrix.org)!

[EasyMotion]: https://github.com/easymotion/vim-easymotion
[vim-plug]: https://github.com/junegunn/vim-plug
[packer]: https://github.com/wbthomason/packer.nvim

