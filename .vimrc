highlight ExtraWhitespace ctermbg=red guibg=red
function! SetCustomMatches()
    silent! call matchdelete(300)
    call matchadd("ExtraWhitespace", '\s\+$', -10, 300)
endfunction

autocmd VimEnter * call SetCustomMatches()
autocmd WinEnter * call SetCustomMatches()

:syntax on
