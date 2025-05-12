function whitespace() {
  # Strip whitespace from every file added to git
  git ls-files | grep -v '\.tgz$' | xargs -I{} sed -i '' 's/[ 	]*$//' {}
}
