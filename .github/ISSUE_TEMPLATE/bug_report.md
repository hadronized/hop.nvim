---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''

---

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
```
-- bootstrap lazy
        local lazypath = root .. "/plugins/lazy.nvim"
        if not vim.loop.fs_stat(lazypath) then
          vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", lazypath, })
        end
        vim.opt.runtimepath:prepend(lazypath)

-- install hop.nvim
        local plugins = {
          { "smoka7/hop.nvim", opts = {} },
        }
        require("lazy").setup(plugins,{})
--- How You use hop...

```
**Expected behavior**
A clear and concise description of what you expected to happen.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**version (please complete the following information):**
 - Nvim version: 
 - hop.nvim version:

**Additional context**
Add any other context about the problem here.
