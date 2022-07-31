" This is the minimal init.vim that is needed to run unit tests
" It basically points to the plenary package so we can kickstart the tests with
" just a few lines
set rtp+=.
set rtp+=../plenary.nvim/

runtime! plugin/plenary.vim

