return {
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    branch = "main",
    build = function()
      local ok, ts = pcall(require, "nvim-treesitter")
      if ok then
        ts.install({
          "bash",
          "lua",
          "vim",
          "vimdoc",
          "markdown",
          "markdown_inline",
          "python",
          "javascript",
          "typescript",
          "json",
          "toml",
          "yaml",
          "go",
          "rust",
        })
      end
    end,
    config = function()
      require("nvim-treesitter").setup({})
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("DotsTreesitter", { clear = true }),
        callback = function()
          pcall(vim.treesitter.start)
        end,
      })
    end,
  },
}
