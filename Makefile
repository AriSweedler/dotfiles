DIR=dotfiles

.PHONY: all
all:
	cp Makefile $(DIR)/Makefile
	cp ~/.bashrc $(DIR)/bashrc
	cp ~/.inputrc $(DIR)/inputrc
	cp ~/.vimrc $(DIR)/vimrc
	cp ~/.gitconfig $(DIR)/gitconfig
	cp ~/.ssh/config $(DIR)/ssh-config
	cp ~/bin/* .
