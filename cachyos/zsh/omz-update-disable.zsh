# oh-my-zsh here is installed via the CachyOS `oh-my-zsh-git` pacman package into
# /usr/share/oh-my-zsh (root-owned, no .git dir), not the usual curl-script git clone.
# Its built-in auto-updater assumes a git clone and fails, so disable the automatic
# check. Must be set before oh-my-zsh.sh is sourced (in ~/.zshrc), which is why this
# lives in ~/.zshenv - sourced before ~/.zshrc for every shell. See README.md.
zstyle ':omz:update' mode disabled
