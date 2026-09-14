-- Lightweight LSP using Neovim 0.12+ native vim.lsp.config API.
-- Avoid deprecated nvim-lspconfig server:setup() (removed in lspconfig v3).

return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      { "williamboman/mason.nvim", opts = {} },
      { "williamboman/mason-lspconfig.nvim" },
    },
    config = function()
      local ok_mason, mason_lsp = pcall(require, "mason-lspconfig")
      if ok_mason then
        mason_lsp.setup({
          ensure_installed = { "lua_ls", "bashls", "pyright" },
          automatic_installation = false,
        })
      end

      local servers = {
        lua_ls = {
          settings = {
            Lua = {
              diagnostics = { globals = { "vim" } },
              workspace = { checkThirdParty = false },
            },
          },
        },
        bashls = {},
        pyright = {},
      }

      for name, opts in pairs(servers) do
        vim.lsp.config(name, opts)
        vim.lsp.enable(name)
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(event)
          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = event.buf, desc = desc })
          end
          map("gd", vim.lsp.buf.definition, "Goto definition")
          map("K", vim.lsp.buf.hover, "Hover")
          map("<leader>rn", vim.lsp.buf.rename, "Rename")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
        end,
      })
    end,
  },
}
