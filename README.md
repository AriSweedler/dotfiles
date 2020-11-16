# Intro

Hi! Welcome to my Dotfiles

"Dotfiles" are configuration files. With this git repo containing all my
dotfiles, any machine can feel like home with a simple `git pull`. (Well,
almost. I just need to get these dotfiles into my home directory. Read
[this](https://www.atlassian.com/git/tutorials/dotfiles) for full details).

Just as a general concept, understand that there're many ways to get input into
a program, and using dotfiles (configuration files) is just one way of many:
1) Hard-code constants
2) Invoke program with parameters (--options)
3) Read configuration files (like these!)
4) Get user input during the program

But why "*dot*files"? Seems random.
* The "dot" makes the file hidden:
  [link](https://linux-audit.com/linux-history-how-dot-files-became-hidden-files/).
  It seems reasonable to have these configuration files hidden, as you only
  wanna edit them when you wanna edit the system. The idea is: when you're being
  a regular user, you shouldn't even have to think about them.
* Referring to them as "hidden files" is too broad. Not all hidden files are
  config files. Referring to them as "config files" is totally reasonable.
  However, not all config files go in your home directory.

Many of these dotfiles have the `rc` suffix. Why?
* [answer](https://stackoverflow.com/a/11030607/7531823)


# My dotfiles

## `.bashrc`, `.bash_profile`, and `.profile`. And also `.zshrc`.
Ahhh, the shell. If you don't know what a shell is, read
[this](https://swcarpentry.github.io/shell-novice/).

As a quick summary, computers have all sorts of capabilities. But they're just
bricks until you're able to interface with them. For escalators, you have
buttons. For personal computers with a desktop, you have icons to click on. For
stuff like Microsoft Word, you have keypresses (including shortcuts).

For computers without graphic user interfaces, you have a shell. Because you
can't click on the program you wanna run, you need to type in the name. Of
course, there're different shells available, as well as different configuration
options available to each shell. You get to define them in these files.

If you don't know what a shell is, don't worry about the difference between
these files quite yet. Once you know what an interactive vs. non-interactive
shell session is, it might be wise to read through this: [`.profile`,
`.bash_profile`, and
`.bashrc`](https://serverfault.com/questions/261802/what-are-the-functional-differences-between-profile-bash-profile-and-bashrc)?

### `.aliases`
I have this as a separate file because I can source this in bash or zsh.

## `.gitconfig`
Git is a great tool. It is very powerful. But sometimes a bit weird to interface
with. If it's confusing, then invest some time into the following steps:
1) What problem does git solve, in general.
2) What is the mental model of how to use git
3) What problem does git solve, for you.

If answering all 3 of those questions is easy, then you'll have no trouble using
it as you desire.

This is a good thing to know: Git reads config files on 3 levels: system, user,
and repo. If you wanna learn git really well, read through
[this](https://git-scm.com/book/en/v2).

Here're some links that were useful when I was learning (aka debugging before I
knew how to debug):
* Peep this quick piece of [documentation](https://git-scm.com/docs/git-config#git-config---global).
* There's ALWAYS a way to [debug](https://git-scm.com/docs/git-config#git-config---show-origin)

## `.vim`
This one is lit. Alright, this is more of a "dotdirectory" instead of a
"dotfile", but it's still called a "dotfile". Don't worry about the literal
meaning of the word "dotfile" too much.

The syntax is all in a language called
[vimscript](https://learnvimscriptthehardway.stevelosh.com/), and it quickly
becomes readable and useful after you learn how to use vim. Modify/personalize
your own! It's a journey.

Personally, my folder structure is as follows:
* `vimrc` - every time vim gets opened. Defines global settings
* `filetype.vim` - If vim doesn't know the filetype, source this file. There's
  actually no technical promise that sourcing this will `set filetype` properly,
  but that's the "right" way to use this.
* `pack` - a folder to contain vim packages. Packages are sets of plugins. I
  have 3 packages: plugins I've written, plugins
  [tpope](https://github.com/tpope)has written, and everything else.
  * Under `pack/pkg_name`, you have 2 folders. `start` ==> load the plugin upon
    startup. `opt` ==> the user may choose to optionally load the plugin
    `packadd <pluginname>`.
* `after` - This is basically like another `.vim` folder, but everything gets
  read at the end. It's best practice to put settings you want to override in
  here
  * `ftplugin` - short for `filetype plugin`. Used for settings specific to
    languages. `xyz.vim` in this folder is executed when `:set filetype=xyz` is
    invoked
  * `syntax` - Same, but for `:set syntax=xyz` instead. 95% of the time these
    two are interchangeable. But in some cases they aren't.

## `.ssh/config`
Another "dotdirectory"! Ok, whatever. Read about all the options
[here](https://www.ssh.com/ssh/config/), or on `man ssh_config`

Super useful!! Instead of writing a full command like `ssh
ari@lnxsrv09.seas.ucla.edu` I can just have a proper ~/.ssh/config, and write
`ssh ucla`. An ~/.ssh/config file is also used by `ssh`-related programs, such
as `ssh-copy-id`, `scp`, `rsync` and others.

I use an `Include` directive so I can write as many `~/.ssh/conf.d/XYZ` ssh
config files on each of my machines as I want. At work, for example, I have an
`~/.ssh/conf.d/team_build` file to ssh into my teams build machines, as well as
a `~/.ssh/conf.d/personal` file to ssh into all of my personal VMs. Just makes
it a bit easier!

## `.inputrc`
Bash itself, as well as many many many programs/subshells use the "GNU
Readline Library" to make command-line text editing less of a nightmare! Try
command line editing in `sh` vs. `bash`, and you'll notice a difference. That
difference you're noticing is readline!

It's pretty sweet. Any time you've been sitting at a terminal and
thought to yourself "ugh, I wish I could do X, but I'm using such
archaic technology that I can't", well, you were wrong. You can. Use the
GNU readline library

The GNU Readline library is seriously powerful. I highly recommend
checking it out and getting used to the default keystrokes. Some of my favorites
include
 * "beginning-of-line" (Control-a)
 * "unix-word-rubout" (Control-w) (deletes the bold *text*)
 * "unix-filename-rubout" (unbound - you decide!) (deletes/the/bold/*text*)
 * "backward-word" (unbound)
 * and much much more.

Check out
[this](https://www.gnu.org/software/bash/manual/html_node/Readline-Init-File.html)
for dry documentation. There's a seriously large number of
commands you have access to when the Readline library is enabled.
(Seriously, check out all of them. If you're on bash, you can run `bind -l`.
For zsh, it's `bindkey`)

Check [this](https://www.computerhope.com/unix/bash/bind.htm) out for a
more beginner-friendly read. (Note, they talk about `/etc/inputrc` - the
which will affect all users - it is system wide. But I use `~/.inputrc`,
because I don't have administrative permissions on all machines I use.)

## `.tmux_conf`

Tmux is a tool I absolutely love. I only have one screen and one brain, but I
commonly want to have multiple different terminal windows open. Tmux lets you do
that, as it's a `*t*erminal *mu*ltiple*x*or`.

What is a multiplexor? Here: [link](https://en.wikipedia.org/wiki/Multiplexer).
A multiplexor is a way to select between multiple inputs. Specifically, it has
multiple inputs, one meta-input to select, and one output.

So I have 1 system window into a terminal running tmux, and all my
terminal-related needs will be in this window. I keep this window full-screened
and pushed to the far left in MacOS, so I always know where my terminal is.

Now, specific to tmux, here's the mental model to use.
* tmux has sessions.
* Sessions have windows
* Windows have panes (panes split the screen)

I personally always use 1 session with multiple windows. Each window has a job
(taking notes, editing source code, being ssh'ed into a VM). And if I need
multiple terminals to complete a job, I'll use multiple panes (if, for example,
I wanna read a man page as I'm building a command)

I would use multiple sessions if I had a use for that, but I tend not to. A
hypothetical use is if I had two responsibilities in my job: monitoring a
customer computer in a way that I'd need multiple windows/panes, and doing all
of my regular work.

In my tmux dotfile, I set up my personal settings, define a statusline to my
liking, and create some macros.

## `.local`
I put random config files in here if I don't want them cluttering up my home
directory. Even though they're all hidden... Confusingly, some things belong in
this repo, but some things don't. It might be wise to have a `.local` folder
where truly nothing belongs in this repo, and an `.ari` folder containing the
repo files in .local. Whatever, I can reorganize later when I know what I want
better.

Realistically I could name this folder anything, but `.local` makes sense to me.

### `bin`
Executable files that I wish to share across machines. By adding `~/.local/bin`
to my `$PATH`, I automatically get access to them in my shell.

### `git`
More config files for git. Ideally, I'd like to have a `~/.git` dotdirectory,
like for vim, but that actually implies that there's a repo with the repo-root
in my home directory. Which is problematic. (That's why I do that weird Atlassian
thing).

Links to documentation
* [`.gitignore`](https://www.git-scm.com/docs/gitignore)
* [`.git_template`](https://git-scm.com/docs/git-init#_template_directory)

### `.gitmodules`
Has to be in the root of the working tree, unfortunately.

Link to documentation:
* [`.gitmodules`](https://www.git-scm.com/docs/gitmodules)

## `.macos`
This is actually a bash script that uses Apple-specific commands to deal with
settings for all sorts of neat features about MacOS. I really just read through
[this dude's `.macos`](https://mths.be/macos) and picked out what I like.

## `README.md`
This file. This isn't a dotfile. I just put it here so when you open up this
repo via GitHub, all this information automatically shows up.
