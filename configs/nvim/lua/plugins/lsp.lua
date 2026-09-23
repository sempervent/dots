-- Lightweight LSP using Neovim 0.12+ native vim.lsp.config API.
-- Avoid deprecated nvim-lspconfig server:setup() (removed in lspconfig v3).

return {
  {
    "neovim/nvim-lspconfig",
    config = function()
      -- Generated from configs/lsp/servers.toml. DOTS owns the PATH-visible
      -- binaries; Neovim only configures and attaches clients.
      local servers = require("config.lsp_servers")

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
