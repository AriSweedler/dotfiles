" Commands:
" p, pick <commit> = use commit
" r, reword <commit> = use commit, but edit the commit message
" e, edit <commit> = use commit, but stop for amending
" s, squash <commit> = use commit, but meld into previous commit
" f, fixup <commit> = like "squash", but discard this commit's log message
" x, exec <command> = run command (the rest of the line) using shell
" b, break = stop here (continue rebase later with 'git rebase --continue')
" d, drop <commit> = remove commit
" l, label <label> = label current HEAD with a name
" t, reset <label> = reset HEAD to a label
" m, merge [-C <commit> | -c <commit>] <label> [# <oneline>]
" .       create a merge commit using the original merge commit's
" .       message (or the oneline, if no original merge commit was
" .       specified). Use -c <commit> to reword the commit message.
"
" These lines can be re-ordered; they are executed from top to bottom.
"
" If you remove a line here THAT COMMIT WILL BE LOST.
"
" However, if you remove everything, the rebase will be aborted.
"

nnoremap <buffer> <unique> P ciwpick<C-c>j0
nnoremap <buffer> <unique> R ciwreword<C-c>j0
nnoremap <buffer> <unique> E ciwedit<C-c>j0
nnoremap <buffer> <unique> S ciwsquash<C-c>j0
nnoremap <buffer> <unique> F ciwfixup<C-c>j0
nnoremap <buffer> <unique> X ciwexec<C-c>j0
nnoremap <buffer> <unique> B ciwbreak<C-c>j0
"nnoremap <buffer> <unique> D ciwdrop<C-c>j0
nnoremap <buffer> <unique> L ciwlabel<C-c>j0
nnoremap <buffer> <unique> T ciwreset<C-c>j0
nnoremap <buffer> <unique> M ciwmerge<C-c>j0