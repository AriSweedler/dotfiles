export LESS_TERMCAP_mb=$(printf '\e[01;31m') 	# begin bold - red
export LESS_TERMCAP_md=$(printf '\e[01;32m') 	# begin blink - green
export LESS_TERMCAP_me=$(printf '\e[0m') 		# leave bold / blink
export LESS_TERMCAP_se=$(printf '\e[0m') 		# leave standout
export LESS_TERMCAP_so=$(printf '\e[01;31m') 	# enter standout - red
export LESS_TERMCAP_ue=$(printf '\e[0m') 		# leave underline
export LESS_TERMCAP_us=$(printf '\e[01;37m') 	# enter underline - white

#readonly prompt_string="%T: 'f?%F:stdin.': %bt/%bb %B ?cSIDEWAYS. ?xNext file: %x.%t"
#readonly flags=(
  #"--status-column"
  #"--Long-prompt"
  #"--Hilite-unread"
  #"--follow-name"
  #"-P${prompt_string}"
#)
#alias less="less ${flags[*]}"
#alias lesss="less"

# TODO write a colorscheme. Or a compiler that takes a YAML file and outputs a colorscheme commands
# b      Blue
# c      Cyan
# g      Green
# k      Black
# m      Magenta
# r      Red
# w      White
# y      Yellow

#  Changes the color of different parts of the displayed text.  x is a single character which selects the type of text whose color is being set:
#  B      Binary characters.
#  C      Control characters.
#  E      Errors and informational messages.
#  M      Mark letters in the status column.
#  N      Line numbers enabled via the -N option.
#  P      Prompts.
#  R      The rscroll character.
#  S      Search results.
#  W      The highlight enabled via the -w option.
#  d      Bold text.
#  k      Blinking text.
#  s      Standout text.
#  u      Underlined text.


#         -kfilename or --lesskey-file=filename
#                Causes less to open and interpret the named file as a lesskey(1) file.  Multiple -k options may be specified.  If the LESSKEY or LESSKEY_SYSTEM environment variable is set,
#                or if a lesskey file is found in a standard place (see KEY BINDINGS), it is also used as a lesskey file.
