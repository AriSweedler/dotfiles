# Hi! Welcome to my bin.

This is where I keep all my executables. It's always a good idea to properly
register content within a system. That let's you implicitly take advantage of
all sorts of features with minimal effort. This is the point of following "best
practices" when diving into a new system or language.

However, make sure you know the difference between "best practice" as an
organziational strategy and "best practice" as an actual hook into an
intelligent system.

So what does `bin` mean? Etymylogically, `bin` is an abbreviation for "binary".
I (and many other people) use it in a slightly more general sense - I save
executable scripts in my bin folder - and they can be text-based instead of
binary. Is that a contradiction? In meaning, yes, but in semantics, no.

Let me explain the semantics. There is a shell environment variable - `echo
"$PATH"` - that determines where your system searches when looking for a command
to execute. It is a `:`-separated list of directory paths. So I register my
personal `bin` folder with the shell's `PATH` variable, and then anything I
write that I want to execute, I simply place into my `bin` folder - it is now
seen as an invokable by my system.

This has 2 advantages:
1) I can invoke it with just the `basename` (instead of the `abspath`)
2) autocomplete! Typing <kbd>d</kbd><kbd>i</kbd><kbd>v</kbd><kbd>Tab</kbd> lets
me quickly call my "divider" function. This is especially neat when used
directly in vim.

Executing the vim command `:read !divider --width 15 --vim ':)'` yields `"""""
:) """""`. Without my `PATH` set up to point to the directory housing `divider`,
I would have to type out the full path (and why would I ever care about the full
path if I just wanna use `divider`)

## divider

Man! Argument parsing in python is rad. Run `divider --help` if you wanna see
what this thing does. It basically just makes it easy for me to create dividers
in my code, just to make it look nice. Give it a quick read, it should be pretty
understandable. It just prints the string you specify in the middle of a
comment, using whatever comment syntax you feel like.

```
##################################### nice #####################################
################################# this is neat #################################
############################## lets call this art ##############################
####################### a haiku would look nice in this ########################
######## view this file in a fixed-width font to see how this lines up #########
```

## notes

For daily note-taking. Sets up a notes repo in `NOTES_BASE` or
`$HOME/Desktop/notes`. Check out my plugin
[vim-notes](https://github.com/AriSweedler/vim-notes) for the vim side of
support for this

## displayplacer

Ripped from [displayplacer
github](https://github.com/jakehilborn/displayplacer). This is just a useful
command. 500 lins of C code that just makes updating the mac display settings
trivially scriptable. Maybe it already was even without this, but I don't know
how. Allows you to do capture (`displayplacer list`) and replace (`displayplacer
$(displayplacer list)`).
