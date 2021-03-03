                                              __
                                             / /_  ____  ____
                                            / __ \/ __ \/ __ \
                                           / / / / /_/ / /_/ /
                                          /_/ /_/\____/ .___/
                                                     /_/
                                      · Neovim motions on speed! ·

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
* [Getting started](#getting-started)
  * [Disclaimer and experimental notice](#disclaimer-and-experimental-notice)
  * [Installation](#installation)
* [Usage](#usage)
* [Configuration](#configuration)

<!-- vim-markdown-toc -->

# Features

- [x] Go to any word in the current buffer.
- [x] Go to any character in the current buffer.
- [x] Go to any bigrams in the current buffer.
- [x] Make an arbitrary search akin to <kbd>/</kbd> and go to any occurrences.
- [x] Go to any line.

![](https://phaazon.net/media/uploads/hop_nvim_jump_words_demo.gif)

![](https://phaazon.net/media/uploads/hop_nvim_modes.gif)

![](https://phaazon.net/media/uploads/hop_nvim_visual_extend.gif)

# Getting started

This section will guide you through the list of steps you must take to be able to get started with **Hop**.

This plugin was written against Neovim 0.5, which is currently a nightly version. However, Neovim 0.4 should work
too. If you are still on Neovim 0.4, feel free to reach out and tell me how is your experience going.

This plugin will not currently work on Vim and no support for Vim is planned.

## Disclaimer and experimental notice

**Please read this section before going on any further.**

The plugin was born from scratch on 5th February of 2021 and, at the time of writing this, is two days old. Even though
it has reached a usable state, it still has some remaining issues to fix. You can get the full list of them with the
embedded help, if you are curious:

```vim
:help hop-limitations-issues
```

If you are encountering any of these issues, **you do not have to open an issue as it is already being actively worked
on.** However, PRs are greatly appreciated.

## Installation

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'phaazon/hop.nvim'
```

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

[EasyMotion]: https://github.com/easymotion/vim-easymotion
