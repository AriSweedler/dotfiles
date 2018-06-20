# Dotfiles

Here're some useful files that I might want on other machines. Every program ever has some sort of configuration associated with it, so don't be surprised.

It's good practice to place a dotfile in your home directory to save information about a program, because that's pretty much the only folder you can guarantee is unique for a user!

## ssh-config
Read about all the options [here](https://www.ssh.com/ssh/config/)

This one is super useful!! Instead of writing `ssh ari@lnxsrv09.seas.ucla.edu` I can just write `ssh ucla`. An ~/.ssh/config file is also used by `ssh`-releated programs, such as `ssh-copy-id`, `scp`, and others.

## bash_aliases, bashrc, gitconfig
These are only readable/useful after you know how to use these tools pretty well. I encourage you to periodically modify/personalize your own! It's a journey.

## inputrc
Bash itself, as well as many many many programs/subshells use the "GNU Readline Library" to make Command-Line text editing less of a nightmare! It's pretty sweet. It used to be, that you could only type. Then, you could type AND hit backspace. THEN!!! You could type, hit backspace, AND use <left>/<right> to navigate and edit stuff.
  
Well, be prepared to have your mind blown, because with a simple inclusion of the GNU readline library into your program, your command line interface can use keybindings like <C-a> to jump to the beginning of a line, <C-w> to delete a word backwards, and much much more. Check out [this](https://www.gnu.org/software/bash/manual/html_node/Readline-Init-File.html) for dry documentation. There's a seriously large number of commands you have access to when the Readline library is enabled. (Seriously, check out all of them with `bind -l`

Check [this](https://www.computerhope.com/unix/bash/bind.htm) out for a more beginner-friendly read. (Note, they talk about `/etc/inputrc`, but I use a `~/.inputrc`)
