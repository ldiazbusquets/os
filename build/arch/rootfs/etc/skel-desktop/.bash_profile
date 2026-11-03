[[ -f ~/.bashrc ]] && . ~/.bashrc
# The screen (tty1) goes straight to the desktop; the serial line stays a plain shell.
if [ "$(tty)" = /dev/tty1 ] && [ -z "$DISPLAY" ]; then exec startx -- -nolisten tcp >/tmp/xorg.log 2>&1; fi
