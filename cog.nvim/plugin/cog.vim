if exists('g:loaded_cog')
  finish
endif
let g:loaded_cog = 1

command! CogStart lua require('cog').start()
command! CogStop lua require('cog').stop()
command! CogChat lua require('cog').open_chat()
command! CogPrompt lua require('cog').prompt()
