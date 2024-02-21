# Intro

Hi! Welcome to my `dotfiles`

"dotfile" is a colloquial name for "configuration file". As they're hidden by
default (try running `ls` with and without out the `-a` flag), they're the
perfect place for applications to store configuration data that they don't want
users changing on accident.

With this git repo, any machine can feel like home with a simple `git pull`.
(Well, almost. I just need to get these dotfiles into my home directory. Read
[this](https://www.atlassian.com/git/tutorials/dotfiles) for full details).

There are many ways to modify the behavior of a program. Per machine, per user,
per instance, etc. Dotfiles are generally per-user. 

1) Hard-code constants
2) Invoke program with parameters (--options)
3) Read configuration files (like these!)
4) Get user input during the program

I try to keep most of my configuration files in the `~/.config/<APP>` folder,
but older systems will still require you to use something like `~/.*<APP>*`.

## Fun facts
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
