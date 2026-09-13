"~/.config/nvim/init.vim - Neovim Configuration
" Based on vimrc but optimized for Neovim

" Use Vim settings, not Vi settings {{{1
set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath

" Source vimrc for shared config {{{1
if filereadable(expand("~/.vimrc"))
  source ~/.vimrc
endif

" Neovim-specific settings {{{1
set termguicolors
let $NVIM_TUI_ENABLE_TRUE_COLOR=1

" Built-in LSP (Language Server Protocol) {{{2
" Use built-in LSP instead of external tools when available
if has('nvim-0.5')
  " LSP configuration will go here
  " Install nvim-lspconfig for full LSP support
endif
" 2}}}

" Terminal mode improvements {{{2
tnoremap <Esc> <C-\><C-n>
tnoremap jj <C-\><C-n>
" 2}}}

" Better clipboard integration {{{2
set clipboard+=unnamedplus
" 2}}}

" Lua config support {{{2
lua << EOF
-- Add lua configs here if desired
-- Example: vim.g.loaded_netrwPlugin = 1
EOF
" 2}}}
" 1}}}

" Plugin manager - vim-plug for Neovim {{{1
if empty(glob('~/.local/share/nvim/site/autoload/plug.vim'))
  silent !curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

call plug#begin('~/.local/share/nvim/plugged')

" Essential plugins {{{2
Plug 'junegunn/vim-plug'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-commentary'
Plug 'airblade/vim-gitgutter'
Plug 'preservim/nerdtree'
Plug 'preservim/nerdcommenter'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

" fzf integration {{{3
if executable('fzf')
  Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
  Plug 'junegunn/fzf.vim'
endif
" 3}}}

" Language support {{{3
Plug 'davidhalter/jedi-vim'
Plug 'neoclide/coc.nvim', {'branch': 'release'}  " Better LSP support
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'nvim-treesitter/nvim-treesitter-textobjects'
" 3}}}

" Colors {{{3
Plug 'tomasr/molokai'
" 3}}}

" Utilities {{{3
Plug 'junegunn/goyo.vim'
Plug 'junegunn/limelight.vim'
Plug 'ntpeters/vim-better-whitespace'
Plug 'jiangmiao/auto-pairs'
" 3}}}
" 2}}}

call plug#end()
" 1}}}

" CoC settings {{{1
" Use tab for trigger completion with characters ahead and navigate
inoremap <silent><expr> <TAB>
      \ coc#pum#visible() ? coc#pum#next(1) :
      \ CheckBackspace() ? "\<Tab>" :
      \ coc#refresh()
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

function! CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Use <cr> to confirm completion
inoremap <expr> <cr> coc#pum#visible() ? coc#pum#confirm() : "\<CR>"

" Use `[g` and `]g` to navigate diagnostics
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

" GoTo code navigation
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K to show documentation in preview window
nnoremap <silent> K :call ShowDocumentation()<CR>

function! ShowDocumentation()
  if CocAction('hasProvider', 'hover')
    call CocActionAsync('doHover')
  else
    call feedkeys('K', 'in')
  endif
endfunction
" 1}}}

" Treesitter {{{1
lua << EOF
require'nvim-treesitter.configs'.setup {
  ensure_installed = { "python", "javascript", "typescript", "bash", "json", "yaml", "markdown" },
  highlight = {
    enable = true,
  },
  indent = {
    enable = true,
  },
}
EOF
" 1}}}


