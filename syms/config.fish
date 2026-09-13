# ~/.config/fish/config.fish - Fish Shell Configuration
# https://github.com/sempervent/dotfiles

# Path to dots directory
set -gx DOTS_DIR $HOME/dots
set -gx SRC_DIR $HOME

# Fish-specific settings {{{1
set -g fish_greeting ""  # Disable default greeting
set -g fish_key_bindings fish_vi_key_bindings  # Vi mode

# Environment variables {{{1
set -gx EDITOR vim
set -gx VISUAL vim
set -gx TERM xterm-256color

# Detect OS
switch (uname -s)
  case Darwin
    set -gx OS Mac
  case CYGWIN MSYS MINGW*
    set -gx OS Win
  case '*'
    set -gx OS Nix
    set -gx LS_OPTS --color=auto
end

# PATH additions
fish_add_path $HOME/scripts
fish_add_path $HOME/.local/bin

if test -n "$JAVA_HOME"
  fish_add_path $JAVA_HOME/bin
end

# macOS Homebrew
if test "$OS" = "Mac"
  if test -d /opt/homebrew
    fish_add_path /opt/homebrew/bin
  else if test -d /usr/local/Homebrew
    fish_add_path /usr/local/bin
  end
end
# 1}}}

# Abbreviations (like aliases but expand) {{{1
abbr -a -- - 'cd -'
abbr -a -- ... '../..'
abbr -a -- .... '../../..'
abbr -a -- less 'less -R'
abbr -a -- ll 'ls -lh'
abbr -a -- la 'ls -lah'
abbr -a -- l 'ls -lh'
abbr -a -- so 'source ~/.config/fish/config.fish'
abbr -a -- reload 'source ~/.config/fish/config.fish'
abbr -a -- gst 'git status'
abbr -a -- gaa 'git add .'
abbr -a -- gcm 'git commit -m'
abbr -a -- gco 'git checkout'
abbr -a -- gpl 'git pull'
abbr -a -- gps 'git push'
abbr -a -- glog 'git log --oneline --graph --decorate --all'
# Docker functions (Fish versions)
function dco
  if command -v docker-compose >/dev/null 2>&1
    docker-compose $argv
  else if docker compose version >/dev/null 2>&1
    docker compose $argv
  else
    echo "Error: Neither 'docker-compose' nor 'docker compose' found"
    return 1
  end
end

function dcud
  if command -v docker-compose >/dev/null 2>&1
    docker-compose down; and docker-compose up -d $argv
  else if docker compose version >/dev/null 2>&1
    docker compose down; and docker compose up -d $argv
  else
    echo "Error: Neither 'docker-compose' nor 'docker compose' found"
    return 1
  end
end

abbr -a -- de 'docker exec -it'
abbr -a -- dps 'docker ps --format "{{.Names}}: {{.Image}} @ {{.CreatedAt}} {{.Status}}"'
# 1}}}

# Functions {{{1
# mkcd - make directory and cd into it
function mkcd
  mkdir -p $argv[1]
  and cd $argv[1]
end

# Extract function
function extract
  switch $argv[1]
    case '*.tar.bz2'
      tar xjf $argv[1]
    case '*.tar.gz'
      tar xzf $argv[1]
    case '*.bz2'
      bunzip2 $argv[1]
    case '*.rar'
      unrar x $argv[1]
    case '*.gz'
      gunzip $argv[1]
    case '*.tar'
      tar xf $argv[1]
    case '*.tbz2'
      tar xjf $argv[1]
    case '*.tgz'
      tar xzf $argv[1]
    case '*.zip'
      unzip $argv[1]
    case '*.Z'
      uncompress $argv[1]
    case '*.7z'
      7z x $argv[1]
    case '*'
      echo "don't know how to extract '$argv[1]' ..."
  end
end

# File count
function file_count
  ls -1 | wc -l | sed 's: ::g'
end

# Quick file search
function f
  find . -name "*$argv*" 2>/dev/null
end

# Quick directory search
function d
  find . -type d -name "*$argv*" 2>/dev/null
end

# Network IP
function my_ip
  curl -s ifconfig.me 2>/dev/null; or curl -s ifconfig.co 2>/dev/null
end

# Weather
function weather
  curl -s wttr.in
end
# 1}}}

# Load shared aliases as functions {{{1
# Fish doesn't support aliases the same way, so we'll use functions
# For simple commands from shared aliases
if test -f "$DOTS_DIR/shared/aliases.sh"
  # Note: Fish can't directly source bash, so we manually define here
  # Or we can use a compatibility layer
end
# 1}}}

# Git prompt {{{1
if functions -q fish_git_prompt
  set -g __fish_git_prompt_showdirtystate yes
  set -g __fish_git_prompt_showstashstate yes
  set -g __fish_git_prompt_showuntrackedfiles yes
  set -g __fish_git_prompt_showupstream yes
  set -g __fish_git_prompt_color_branch yellow
  set -g __fish_git_prompt_color_dirtystate red
  set -g __fish_git_prompt_color_stagedstate green
end

# Custom prompt
function fish_prompt
  set_color -o blue
  echo -n (whoami)
  set_color normal
  echo -n '@'
  set_color -o cyan
  echo -n (hostname)
  set_color normal
  echo -n ' '
  set_color -o yellow
  echo -n (prompt_pwd)
  set_color normal
  if functions -q fish_git_prompt
    echo -n (fish_git_prompt)
  end
  echo -n ' '
  set_color -o green
  echo -n '$ '
  set_color normal
end

function fish_right_prompt
  set_color magenta
  date '+%H:%M:%S'
end
# 1}}}

# OS-specific configuration {{{1
if test "$OS" = "Mac"
  if test -f "$DOTS_DIR/distro/mac.sh"
    # Fish can't source bash files directly, but we can run them
    # For macOS-specific setup, consider creating a fish version
  end
end
# 1}}}

# nvm (Node Version Manager) {{{1
if test -s "$HOME/.nvm/nvm.sh"
  function nvm
    bass source "$HOME/.nvm/nvm.sh" ';' nvm $argv
  end
  
  # Auto-use .nvmrc if present
  function __check_nvm --on-variable PWD --description 'Do nvm stuff'
    if test -f .nvmrc
      nvm use
    end
  end
end
# 1}}}

# rustup (Rust toolchain manager) {{{1
if test -f "$HOME/.cargo/env"
  bass source "$HOME/.cargo/env"
end
# 1}}}

# fzf integration {{{1
if test -f "$HOME/.fzf/shell/key-bindings.fish"
  source "$HOME/.fzf/shell/key-bindings.fish"
end
# 1}}}

# Tmux auto-attach {{{1
if command -v tmux >/dev/null
  and test -z "$TMUX"
  and test -n "$SSH_TTY"
  set ID (tmux ls 2>/dev/null | grep -vm1 attached | cut -d: -f1)
  if test -z "$ID"
    tmux new-session
  else
    tmux attach-session -t "$ID"
  end
end
# 1}}}

# Welcome message {{{1
if test -n "$SSH_TTY"; or test -z "$TMUX"
  echo "Welcome, "(whoami)"!"
  if command -v fortune >/dev/null
    if command -v cowsay >/dev/null
      if command -v lolcat >/dev/null
        fortune | cowsay | lolcat
      else
        fortune | cowsay
      end
    else
      fortune
    end
  end
end
# 1}}}

