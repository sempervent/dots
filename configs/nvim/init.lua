-- DOTS Neovim bootstrap (lazy.nvim)
-- Migrated from Vim/Vundle + legacy init.vim → native Lua.
-- Do not source ~/.vimrc forever; keep Vim config as legacy-only.

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("config.options")
require("config.keymaps")
require("config.autocmds")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  change_detection = { notify = false },
  ui = { border = "rounded" },
  install = { colorscheme = { "catppuccin" } },
})
