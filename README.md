# Hi! Welcome to my Dotfiles

Here're some useful files that I might want on other machines. Every
program ever has some sort of configuration associated with it, so don't
be surprised.

It's good practice to place a dotfile in your home directory to save
information about a program, it's a standard filesystem location that's
guaranteed to be unique for a user.

Make sure you use `-a` when using `ls` in this folder ahaha. To start off, I'll talk about the only two NON-dotfiles here.

## update.sh
This script allows me to edit literal dotfiles and run this command to place
them in this repo. Or, update the repo and update my dotfiles! Neat. There're
a few TODOs for this script.
    * Make a machine-specific folder (.local/<machine> for stuff where I want a
    different PS1
    * Figure out what else would be neat!

## fresh.sh
A script to curl and pipe into bash, it helps set up a fresh new machine for
me. To be invoked with bash <(curl --silent
https://raw.githubusercontent.com/AriSweedler/dotfiles/master/fresh.sh)

## ssh-config
Read about all the options [here](https://www.ssh.com/ssh/config/)

This one is super useful!! Instead of writing
`ssh ari@lnxsrv09.seas.ucla.edu` I can just write `ssh ucla`.
An ~/.ssh/config file is also used by `ssh`-releated programs, such as
`ssh-copy-id`, `scp`, `rsync` and others.

## bashrc, gitconfig, vimrc, and bash_aliases
These quickly become readable and useful after you learn how to use
these tools. Modify/personalize your own! It's a journey.

 * bashrc isn't being sourced? You probably have a bash_profile.
    * [What's the difference](https://serverfault.com/questions/261802/what-are-the-functional-differences-between-profile-bash-profile-and-bashrc)?
 * Config options in git are showing up that you didn't put there?
    * Peep this quick piece of [documentation](https://git-scm.com/docs/git-config#git-config---global).
    * There's ALWAYS a way to [debug](https://git-scm.com/docs/git-config#git-config---show-origin)

## inputrc
Bash itself, as well as many many many programs/subshells use the "GNU
Readline Library" to make command-line text editing less of a nightmare!
It's pretty sweet. Any time you've been sitting at a terminal and
thought to yourself "ugh, I wish I could do X, but I'm using such
archaic technology that I can't", well, you were wrong. You can. Use the
GNU readline library

Do be aware that the readline library is open sourced under the GNU GPL,
which means that for a tool to use it, it must fully disclose it's
source. So, yeah. That's why you need to use `rlwrap` on proprietary
tools.

The GNU Readline library is seriously powerful. I highly recommend
checking it out and getting used to the keystrokes. Some of my favorites
include
 * "beginning-of-line" (Control-a)
 * "unix-word-rubout" (Control-w) (deletes the bold *text*)
 * "unix-filename-rubout" (unbound - you decide!) (deletes/the/bold/*text*)
 * "backward-word" (unbound)
 * and much much more.

Check out [this](https://www.gnu.org/software/bash/manual/html_node/Readline-Init-File.html) for dry documentation. There's a seriously large number of
commands you have access to when the Readline library is enabled.
(Seriously, check out all of them with `bind -l`)

Check [this](https://www.computerhope.com/unix/bash/bind.htm) out for a
more beginner-friendly read. (Note, they talk about `/etc/inputrc`,
which will affect all users - it is system wide. But I use `~/.inputrc`,
because I don't have administrative permissions on all machines I use.)

## PS1.sh

Here's a script that'll help you create a custom-made PS1. You can have a fun prompt script really easily! [Source](https://stackoverflow.com/questions/45761508/whats-the-difference-between-script-or-source-script-bash-script) the shell script upon startup. You can use your ~/.bashrc for this. [Here](https://unix.stackexchange.com/questions/129143/what-is-the-purpose-of-bashrc-and-how-does-it-work) is more info on the different run command files.

Boom! Just like that, you have a neat and fancy PS1. Now dive into the script and edit it if you want! All the color variables at the top are escape codes. So instead of being printed out, they simply set the terminal's pen color.

Check out the following links for more details:

1. Check out the [bash man page](https://linux.die.net/man/1/bash), the section titled "Prompting" (What does '\W' do?)

1. Learn more about escape codes for pretty colors in bash [here](https://misc.flogisoft.com/bash/tip_colors_and_formatting)

