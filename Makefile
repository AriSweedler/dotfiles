.PHONY: all save restore

all:
	@echo saving settings by default

save:
	cp ~/.bashrc bashrc
	cp ~/.inputrc inputrc
	cp ~/.vimrc vimrc
	cp ~/.gitconfig gitconfig
	cp ~/.ssh/config ssh-config

restore:
	cp bashrc ~/.bashrc
	cp inputrc ~/.inputrc
	cp vimrc ~/.vimrc
	cp gitconfig ~/.gitconfig
	cp ssh-config ~/.sh/config 

