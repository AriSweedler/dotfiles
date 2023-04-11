" If I have a bunch of functions, this is helpful.
setlocal foldmethod=manual
setlocal foldcolumn=3
function! s:make_folds()
  setlocal foldlevel=10
  normal zE
  let foldables = [
\   "pipeline {$",
\   "stages {$",
\   "stage(.*) {$",
\   "steps {$",
\   "agent {$",
\   "when {$",
\   "script {$",
\   "node(.*) {$",
\   "withCredentials(.*) {$",
\   "docker.image(.*).inside(.*) {$",
\
\   "sshagent.*{$",
\
\   "always {$",
\   "failure {$",
\   "success {$",
\   "unstable {$",
\   "cleanup {$",
\   "post {$",
\   "options {$",
\   "environment {$",
\   "parameters {$",
\   "try {$",
\   "^\\s\\+catch.*{$",
\   "^\\s\\+finally {$",
\
\   "each {.*->$",
\   "def.*(.*) {$",
\   "if (.*) {$",
\   "else {$",
\ ]
  for pat in foldables
    execute "silent global/".pat."/normal $zfaBzO"
  endfor

  " Special case for the global [associative] arrays in our Jenkinsfile
  silent global/^def \w\+ = \[$/normal $zfa]zO

  " Fold everything above and below 'pipeline'
  silent global/^pipeline {$/normal $%2jzfGzO
  silent global/^pipeline {$/normal 2kVgg}zf

  setlocal foldlevel=0
endfunction
call s:make_folds()

setlocal autoindent tabstop=2 expandtab
