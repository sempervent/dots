#!/usr/bin/env bash
# Aliases {{{1
#------------------------------------
alias less='less --color-always --RAW-CONTROL-CHARS'
alias grep='grep --color=auto'
alias agrep='agrep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias stopcolors='sed "s/\[^[[0-9;]*[a-zA-Z]//gi"'
alias aptinstall='sudo aptitude install'
alias bullshit="curl -s http://cbsg.sourceforge.net/cgi-bin/live | grep -Eo '<li>(.*?)</li>' | sed -e 's/<[^>]*>//g' | shuf -n 1 | cowsay -f kosh"
alias lstree="ls -R | grep \":$\" | sed -e 's/:$//' -e 's/[^-][^\/]*\//--/g' -e 's/^/   /' -e 's/-/|/' | less"
alias suspend="sudo systemctl suspend"
# only source chromium aliases if it is installed
if [ -x "$(command -v chromium)" ]; then
  alias trello="chromium --app=https://trello.com"
  alias google="chromium --app=https://google.com"
  alias reddit="chromium --app=https://www.reddit.com"
  alias gmail="chromium --app=https://mail.google.com"
fi
alias reboot="sudo shutdown -r now"
alias python="python3"
alias tmux='TERM=xterm-256color tmux'
alias dco='docker-compose'
alias de='docker exec -it'
alias ffs='sudo "$BASH" -c "$(history -p !!)"'
alias osupgrade="yay -Syua --noconfirm"
# 1}}}
# if file .bash_aliases exists, respect them also
if [ -f "$HOME/.bash_aliases" ]; then
  source "$HOME/.bash_aliases"
fi
alias dcud='docker-compose down && docker-compose up -d'
alias dps='docker ps --format "{{.Names}}: {{.Image}} @ {{.CreatedAt}} {{.Status}}"'
alias less='less --RAW-CONTROL-CHARS'
if [ "$OS" != "Mac" ]; then
	alias ls='ls ${LS_OPTS}'
fi
alias so='source "$HOME/.bashrc"'
alias grep='grep --color=auto'
alias stopcolors='sed "s/\[^[[0-9;]*[a-za-z]//gi"'
alias aptinstall='sudo aptitude install'
alias bullshit="curl -s http://cbsg.sourceforge.net/cgi-bin/live | grep -Eo '<li>(.*?)</li>' | sed -e 's/<[^>]*>//g' | shuf -n 1 | cowsay -f kosh"
alias my_ip="curl ifconfig.me"
alias lstree="ls -R | grep ":\$" | sed -e 's/:$//' -e 's/[^-][^\/]*\//--/g' -e 's/^/   /' -e 's/-/|/' | less"
alias suspend="sudo systemctl suspend"
alias weather='curl wttr.in'
alias dco='docker-compose'
alias show_pymodule='tree -a -I *.egg -I *.pyc -I "__pycache__|build|dist|.egg|.git|.pytest_cache" --prune | less -r'
