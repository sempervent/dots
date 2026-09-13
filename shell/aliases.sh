# shellcheck shell=bash
# Shared aliases (Bash + Zsh compatible POSIX-ish bash)
# Prefer graceful fallbacks when modern tools are missing.

# Color / display
alias less='less --RAW-CONTROL-CHARS'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

if [ "${OS:-}" != "Mac" ] && [ -n "${LS_OPTS:-}" ]; then
  # shellcheck disable=SC2139
  alias ls="ls ${LS_OPTS}"
fi

# eza (modern ls) with fallback
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias ll='eza -lh --group-directories-first --git'
  alias la='eza -lah --group-directories-first --git'
  alias l='eza -lh --group-directories-first'
  alias tree='eza --tree'
else
  alias ll='ls -lh'
  alias la='ls -lah'
  alias l='ls -lh'
fi

# File / system
alias lstree="ls -R 2>/dev/null | grep \":\$\" | sed -e 's/:$//' -e 's/[^-][^\/]*\//--/g' -e 's/^/   /' -e 's/-/|/' | less"
alias suspend='sudo systemctl suspend 2>/dev/null || echo "systemctl suspend not available"'
alias reboot='sudo shutdown -r now 2>/dev/null || sudo reboot 2>/dev/null || echo "reboot not available"'
alias osupgrade='yay -Syua --noconfirm 2>/dev/null || brew upgrade 2>/dev/null || echo "No supported package manager found"'

# Browser apps
if command -v chromium >/dev/null 2>&1; then
  alias trello='chromium --app=https://trello.com'
  alias google='chromium --app=https://google.com'
  alias reddit='chromium --app=https://www.reddit.com'
  alias gmail='chromium --app=https://mail.google.com'
elif command -v open >/dev/null 2>&1; then
  alias trello='open -a "Google Chrome" https://trello.com'
  alias google='open -a "Google Chrome" https://google.com'
  alias reddit='open -a "Google Chrome" https://www.reddit.com'
  alias gmail='open -a "Google Chrome" https://mail.google.com'
fi

# Language conveniences
alias python='python3'
alias pip='pip3'

# Docker
alias de='docker exec -it'
alias dps='docker ps --format "{{.Names}}: {{.Image}} @ {{.CreatedAt}} {{.Status}}"'

# Network / weather
alias my_ip='curl -s ifconfig.me 2>/dev/null || curl -s ifconfig.co 2>/dev/null || echo "Unable to get IP"'
alias weather='curl -s wttr.in 2>/dev/null || echo "Weather service unavailable"'

# Modern tools with fallbacks
if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never'
  alias catt='bat'
  alias catp='bat --paging=always'
fi

if command -v fd >/dev/null 2>&1; then
  alias fdf='fd'
fi

if command -v rg >/dev/null 2>&1; then
  alias rgf='rg --files'
fi

if command -v dust >/dev/null 2>&1; then
  alias du='dust'
fi

if command -v htop >/dev/null 2>&1; then
  alias top='htop'
elif command -v btop >/dev/null 2>&1; then
  alias top='btop'
fi

# Note: do not alias jq/yq with forced color — breaks scripts expecting raw output.
# Use jq-pretty / yq-pretty helpers in shell/functions.sh instead.

# Fun tools
if command -v figlet >/dev/null 2>&1; then
  alias fig='figlet'
fi
if command -v cowsay >/dev/null 2>&1; then
  alias cow='cowsay'
fi
if command -v lolcat >/dev/null 2>&1; then
  alias rainbow='lolcat'
fi
if command -v fortune >/dev/null 2>&1 && command -v cowsay >/dev/null 2>&1 && command -v lolcat >/dev/null 2>&1; then
  alias happy='fortune | cowsay | lolcat'
fi

alias bullshit="curl -s http://cbsg.sourceforge.net/cgi-bin/live 2>/dev/null | grep -Eo '<li>(.*?)</li>' | sed -e 's/<[^>]*>//g' | shuf -n 1 | cowsay -f kosh 2>/dev/null || echo 'Bullshit generator unavailable'"

# Development
alias show_pymodule='tree -a -I "*.egg|*.pyc|__pycache__|build|dist|.egg|.git|.pytest_cache" --prune 2>/dev/null | less -r || find . -name "*.py" | less'

# Git shortcuts (OMZ git plugin may also define these; keep personal short forms)
if command -v git >/dev/null 2>&1; then
  alias gst='git status'
  alias gaa='git add .'
  alias gcm='git commit -m'
  alias gco='git checkout'
  alias gpl='git pull'
  alias gps='git push'
  alias glog='git log --oneline --graph --decorate --all'
fi

# Personal reload helpers differ per shell — defined in bashrc / zshrc
