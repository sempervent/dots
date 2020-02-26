# Aliases {{{1
#------------------------------------
alias less='less --RAW-CONTROL-CHARS'
if [[ "$OS" != "Mac" ]]; then
	echo 'not applying color to ls'
	alias ls='ls --color'
elif [[ "$OS" == 'Mac' ]]; then
	alias ls="/usr/local/Cellar/coreutils/8.31/libexec/gnubin/ls $LS_OPTS"
fi
# export GREP_OPTIONS='--color=auto'
alias grep='grep --color=auto'
alias agrep='agrep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias stopcolors='sed "s/\[^[[0-9;]*[a-zA-Z]//gi"'
alias aptinstall='sudo aptitude install'
alias bullshit="curl -s http://cbsg.sourceforge.net/cgi-bin/live | grep -Eo '<li>(.*?)</li>' | sed -e 's/<[^>]*>//g' | shuf -n 1 | cowsay -f kosh"
alias lstree="ls -R | grep \":$\" | sed -e 's/:$//' -e 's/[^-][^\/]*\//--/g' -e 's/^/   /' -e 's/-/|/' | less"
alias suspend="sudo systemctl suspend"
alias trello="chromium --app=https://trello.com"
alias rstudio="chromium --app=http://192.168.1.178:8787"
alias google="chromium --app=https://google.com"
alias reddit="chromium --app=https://www.reddit.com"
alias gmail="chromium --app=https://mail.google.com"
alias heimdall="chromium --app=https://172.16.0.79/"
alias reboot="sudo shutdown -r now"
alias python="python3"
alias tmux='TERM=xterm-256color tmux'
alias dco='docker-compose'
alias de='docker exec -it'
# prevent use of nano everywhere
alias nano=vim
alias ffs='sudo "$BASH" -c "$(history -p !!)"'
alias osupgrade="yay -Syua --noconfirm"
# 1}}}
# if user .bash_aliases exists, respect them also
if [ -f ~/.bash_aliases ]; then
  source ~/.bash_aliases
fi
alias naermData='ssh 6ng@129.219.184.60'
