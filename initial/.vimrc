set number "set linenumber
set autoindent "set autoindent
set autoread "reload when file is changed in other programs
set autowrite "save when opening an other file
set shiftwidth=4 "width of autoindent
set ts=4 "Tab size
set showmatch "brackek highlight
set smartindent "autoindent according code type
set smarttab "Delete tabsize when click BS
set mouse=a "Using mouse scroll in vim
set clipboard=unnamedplus

if has("syntax")
    syntax on
endif

au BufReadPost *
\ if line("'\"") > 0 && line("'\"") <= line("$") |
\ exe "norm g`\"" |
\ endif

colorscheme slate

