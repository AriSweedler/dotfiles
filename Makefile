# I probably wanna use a shell script instead of a Makefile for this,
# but I'll have a makefile for now.

# When I DO start making a shellscript, I'll wanna check out customized
# tab completion – check [this](https://stackoverflow.com/questions/10942919/customize-tab-completion-in-shell#10947749) out

DOTFILES=bashrc inputrc vimrc gitconfig bash_aliases
.PHONY: all save restore

all: save
	@echo saving settings by default

save:
	cp ~/.bash_aliases bash_aliases
	cp ~/.bashrc bashrc
	cp ~/.gitconfig gitconfig
	cp ~/.inputrc inputrc
	cp -r ~/.iterm iterm
	cp ~/.ssh/config ssh-config
	cp ~/.vimrc vimrc
	cp -r ~/.vim vim

diff:
	-diff bash_aliases ~/.bash_aliases
	-diff bashrc ~/.bashrc
	-diff gitconfig ~/.gitconfig
	-diff inputrc ~/.inputrc
	-diff ssh-config ~/.ssh/config
	-diff vimrc ~/.vimrc
	-diff vim ~/.vim

restore:
	cp bash_aliases ~/.bash_aliases
	cp bashrc ~/.bashrc
	cp gitconfig ~/.gitconfig
	cp inputrc ~/.inputrc
	cp -r iterm ~/.iterm
	cp ssh-config ~/.ssh/config
	cp vimrc ~/.vimrc
	cp -r vim ~/.vim

