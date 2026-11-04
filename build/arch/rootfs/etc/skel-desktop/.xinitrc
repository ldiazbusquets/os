#!/bin/sh
xset s off -dpms s noblank
xrandr --output Virtual-1 --mode 1280x720 2>/dev/null
# tell the build and the page that the desktop is up
(sleep 20; echo GUI_READY > /dev/ttyS0) &
exec dbus-launch --exit-with-session startxfce4
