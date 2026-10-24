function whitespace() {
  # Strip whitespace from every file added to git
  git ls-files | grep -Ev '\.(tgz|gif|png|j.?pg)$' | xargs -I{} sed -i '' 's/[ 	]*$//' {}
}
