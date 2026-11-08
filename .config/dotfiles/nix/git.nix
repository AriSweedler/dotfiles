# Git: ~/.config/git/config and ~/.config/git/ignore, written by home-manager from the blocks
# below (one per former ~/.config/git/plugin/*.gitconfig). An edit takes effect at the next
# `dotfiles switch`. `git config --global` cannot write here (the file is in the store): put a
# setting in this module, or in ~/.local/share/git/config, which every repo under HOME includes.
# The scripts git runs by path (git/bin, the dotfiles hooks, git/template) stay linked files.
{ lib, ... }:
let
  base = {
    user = {
      name = "Ari Sweedler";
      email = "ari@sweedler.com";
      username = "ari.sweedler";
    };
    core = {
      excludesFile = "~/.config/git/ignore";
      editor = "nvim";
    };
    init = {
      templateDir = "~/.config/git/template";
      defaultBranch = "main";
    };
    pull.ff = "only";
    fetch.writeCommitGraph = true;
    stash.showPatch = true;
    alias = {
      # Easily edit this file (then `dotfiles switch`)
      cconfig = "!\${EDITOR:-nvim} ~/dotfiles/.config/dotfiles/nix/git.nix";

      # View these aliases more easily
      alias = "!git config --list | grep ^alias | cut -c 7- | sort #";
      showme = "!printf \"The alias '$1' is: \"; git config --list | sed /alias.$1=/!d | sed s/[^=]*=// #";

      # shorten
      a = "!git add .; git status";
      d = "diff --staged --diff-algorithm=minimal";
      els = "editdiffls";
      f = "fetch --append --prune --jobs=4";
      ff = "pull --ff-only";
      rr = "rebase-remote";
      fpr = "finish-pr";
      po = "push-origin";
      sw = "!git yankbranch; git switch -";

      # New commands
      diffls = "diff --name-only";
      editdiffls = "!f() { refspec=\${1:-@}; files=$(git diff --name-only \${refspec}); [ -n \"\${files}\" ] && $EDITOR -p \${files} || echo \"no changes since ref='\${refspec}'\" ;}; f";
      ignore = "!f() { echo $1 >> .gitignore; }; f";
      ignoree = "!f() { echo $1 >> .git/info/exclude; }; f";
      initt = "!git init; git commit --allow-empty --message 'first commit'";
      ls = "ls-tree --full-tree -r --abbrev HEAD";
      push-origin = "!git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)";
      rebase-remote = "!f() { b=\${1:?provide a branch}; o=\${2:-origin} ; git fetch \${o} && git rebase -i \${o}/\${b} && git branch -f \${b} \${o}/\${b}; }; f";
    };
  };

  color = {
    color.branch = {
      current = "red reverse";
      local = "blue";
      remote = "green";
    };
    color.diff = {
      meta = "yellow black bold";
      frag = "magenta black bold";
      old = "red bold";
      new = "green bold";
      plain = "white";
    };
    color.status = {
      added = "green black bold";
      changed = "yellow black bold";
      untracked = "red reverse bold";
    };
  };

  delta = {
    core.pager = "delta";
    interactive.diffFilter = "delta --color-only";
    delta = {
      navigate = true; # n and N move between diff sections
      file-modified-label = "Δ✏️";
      file-added-label = "Δ🌱";
      file-removed-label = "Δ💥";
      file-renamed-label = "Δ🔀";
      file-copied-label = "Δ👯";
      plus-style = "syntax '#003800'";
      minus-style = "syntax '#3f0001'";
    };
    alias = {
      show-sbs = "-c delta.features=side-by-side show";
      diff-sbs = "-c delta.features=side-by-side diff";
      d-sbs = "-c delta.features=side-by-side diff --staged";
      diff-f = "-c delta.navigate-regex='^(commit|added:|removed:|renamed:|@)' diff";
      d-f = "-c delta.navigate-regex='^(commit|added:|removed:|renamed:|@)' diff --staged";
    };
  };

  dotfiles.alias = {
    # The plain clone ~/dotfiles, or the bare repo ~/dotfiles.git before it (git/bin/git-dotfiles).
    dotfiles = "!\"$HOME/.config/git/bin/git-dotfiles\"";
    df = "dotfiles";
    # Per-machine bare repo for ~/.local. Its remote is a private repo of this machine's own, so
    # machines never share it. A machine may have none (the local tier then stays on it):
    # `git ldf push` says so and exits 0 instead of failing.
    local-dotfiles = "!f() { d=\"$HOME/.local/local-dotfiles.git/\"; if [ \"\${1:-}\" = push ] && [ -z \"$(git --git-dir=\"$d\" remote)\" ]; then echo \"git ldf: no remote; the local tier stays on this machine, nothing to push\" >&2; return 0; fi; git --git-dir=\"$d\" --work-tree=\"$HOME/.local\" \"$@\"; }; f";
    ldf = "local-dotfiles";
  };

  clipboard.alias = {
    log-to-clipboard = "!f() { git log -1 --pretty=format:\"\${1:?}\" \${@:2} | tee /dev/tty | pbcopy; echo; }; f";
    descr = "log-to-clipboard '%B'";
    h = "log-to-clipboard '%h'";
    hash = "log-to-clipboard '%H'";

    swr = "switch-recent";
    wb = "wipebranch";
    yb = "yankbranch";

    switch-recent = "!f() { git branch --format=\"%(refname:short)\" --sort=-committerdate | fzf --header \"Switch to recent branch\" --preview 'git diff {1} --color=always | delta' | xargs git switch; }; f";
    wipebranch = "!f() { git branch -D $1; git push origin --delete $1; }; f";
    yankbranch = "!git branch --show-current | tee /dev/tty | tr -d '\n' | pbcopy";
  };

  # Searching: 'git log -S' searches changes, 'log --grep' commit messages.
  grep.alias = {
    grepp = "grep --break --heading --line-number";
    grep-code = "ll -S";
    grep-commit = "ll --all --grep";
  };

  jujutsuInspired = {
    alias = {
      amend = "commit --amend --reuse-message=HEAD";
      fixup = "!f() { git commit --fixup \"\${1:?}\" && git rebase --autosquash \"\${1:?}~\" ; } ; f";
      patch = "add --patch";
      reword = "commit --amend";
      unadd = "!f() { echo git restore --staged \${1:-.} ; }; f";
    };
    interactive.singleKey = true;
  };

  log = {
    alias = {
      l = "ll -10";
      ll = "log --pretty=newlog --graph";
    };
    # https://git-scm.com/docs/pretty-formats
    # %C(color) color directive; %<(N,TX) next placeholder at least N columns, truncated per TX;
    # %h abbreviated hash; %ar author date, relative; %an author name; %s subject;
    # %w(width,indent1,indent2) line wrap; + a linefeed before a non-empty expansion; %d ref names.
    # TODO the ref names aren't being colored. This looks like a bug.
    pretty.newlog = lib.concatStrings [
      "format:"
      "%C(cyan)%<(9,trunc)%h "
      "%C(green)%<(12,trunc)%ar "
      "%C(dim white)%<(12,trunc)[%an]%C(reset) "
      "%C(reset)%s "
      "%C(bold reverse cyan)%w(0,0,8)%+d"
      "%C(reset)"
    ];
  };

  # Uses file mtime on the ref, not committerdate, because committerdate reflects when the commit
  # was authored, not when it was fetched.
  maintenance.alias = {
    # Prefetch refs (updated by `git maintenance` on a schedule)
    last-prefetched = "!f() { ref_file=\"$(git rev-parse --git-dir)/refs/prefetch/remotes/\${1:?usage: git last-prefetched <remote/branch>}\"; if [ -f \"$ref_file\" ]; then stat -f '%Sm' \"$ref_file\"; else echo \"no prefetch ref for $1\"; fi; }; f";
    last-prefetched-main = "!git last-prefetched origin/main";
    lpfm = "last-prefetched-main";

    # Regular refs (updated by `git fetch`)
    last-fetched = "!f() { ref_file=\"$(git rev-parse --git-dir)/refs/remotes/\${1:?usage: git last-fetched <remote/branch>}\"; if [ -f \"$ref_file\" ]; then stat -f '%Sm' \"$ref_file\"; else echo \"no ref for $1\"; fi; }; f";
    last-fetched-main = "!git last-fetched origin/main";
    lfm = "last-fetched-main";
  };

  mergetool = {
    merge = {
      tool = "nvimdiff";
      conflictStyle = "zdiff3";
    };
    mergetool = {
      # No .orig copy of the file with conflict markers after a merge
      keepBackup = false;
      # Don't prompt before each invocation of the merge resolution program
      prompt = false;
      # Use temporary directory for cleaner file names
      writeToTemp = true;
      # Multi-tab layout: 1) REMOTE only, 2) REMOTE vs LOCAL, 3) 4-way view.
      # ':cquit' exits with code 1 to abort the merge; ':wqall' accepts the changes.
      nvimdiff.layout = "@REMOTE + REMOTE,LOCAL + REMOTE,MERGED,LOCAL / BASE";
    };
  };

  pr.alias = {
    pr = "!gh pr create --fill; git pro";
    pro = "!f() { branch=\"\${1:-$(git branch --show-current)}\"; gh pr list --head \"$branch\" --state all --json url -q '.[0].url' | xargs open; }; f";
    dim = "!git delete-if-merged-all '^ari-sweedler/'";
  };

  rebase.rebase = {
    # Rebasing branch A onto main moves the commits, not the refs: a branch B pointing into A is
    # left on the old commit. updateRefs moves B too (origin/B then no longer fast-forwards).
    updateRefs = true;
    # Stash before a rebase and unstash after, so a dirty working tree does not block it.
    autoStash = true;
    autosquash = true;
  };

  # Reuse recorded resolution: record a hand-resolved merge conflict, reuse it when the same
  # conflict comes back.
  rerere.rerere.enabled = true;

  submodules = {
    submodule.recurse = true;
    push.recurseSubmodules = "on-demand";
    diff.submodule = "diff";
    alias = {
      sub-u = "sub-update";
      push-all = "sub-push";
      sub-push = "!f() { git submodule foreach git push && git push; }; f";
      sub-all = "submodule foreach git";
      # A no-op in a submodule whose HEAD is detached
      sub-ff = "submodule foreach git pull --ff-only";
      # Leaves HEAD detached, unless submodule.<name>.branch is set (then origin/<branch>)
      sub-update = "submodule update --remote";
    };
  };
in
{
  programs.git = {
    enable = true;
    settings = lib.mkMerge [
      base
      color
      delta
      dotfiles
      clipboard
      grep
      jujutsuInspired
      log
      maintenance
      mergetool
      pr
      rebase
      rerere
      submodules
    ];
    # This machine's settings, last so they override the above; `git maintenance register`
    # keeps its repo list here.
    includes = [{ condition = "gitdir:~/"; path = "~/.local/share/git/config"; }];
    ignores = [
      # vim
      ".*.swp"
      "*.add.spl"
      "tags"
      ".codereview.nvim"

      # OS generated files
      ".DS_Store*"

      # No need to back this up
      ".ssh"
      ".local"

      # The bare shared repo, before the plain clone
      "dotfiles.git"

      # Misc utilities
      ".cache"

      # Python
      ".env"
      ".env.local"
      ".venv"
      ".pyenv"
      "__pycache__/"
      "*.pyc"

      # delve
      "__debug_bin*"

      # Claude
      "**/.claude"
      ".worktrees"
      "thoughts"
      ".bk.yaml"
      "bk.yaml"

      # Datadog ddviz panel runtime state (socket lock, pid)
      ".ddviz"

      # Cloudflare wrangler CLI state
      ".wrangler"
    ];
  };
}
