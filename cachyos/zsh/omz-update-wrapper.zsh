# Redirect `omz update` to pacman since oh-my-zsh is a pacman package here,
# not a git clone; keep all other `omz` subcommands (theme, plugin, etc.) working.
functions[_omz_orig]=$functions[omz]
omz() {
  if [[ "$1" == "update" ]]; then
    echo "oh-my-zsh is managed via pacman here — updating with pacman instead:"
    sudo pacman -Syu oh-my-zsh-git
  else
    _omz_orig "$@"
  fi
}
