# Seed tree for the fake shared-dotfiles remote used by the tests.

seed_df_remote copies this tree, adds the Brewfile, exclude template, lib/, bin/ and the log libs
from the checkout under test, and commits it into $FIX/remotes/dotfiles.git. Scripts here are test
doubles for the real ~/.config/bin/git-health and ~/.config/claude/bin/initialize.sh.
