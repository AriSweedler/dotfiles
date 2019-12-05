" Give the 'verilog' filetype to testbench files
au BufNewFile,BufRead *.tb setf verilog

" Give the 'yacc' filetype to explicitly named .yacc files
au BufNewFile,BufRead *.yacc setf yacc

" Give the 'make' filetype to 'Make include' files
au BufNewFile,BufRead Makefile.inc setf make

" TODO do these belong in teir own file?
