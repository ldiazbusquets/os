#!/bin/sh
xset s off -dpms s noblank
# tell the build and the page that the desktop is up
(sleep 20; echo GUI_READY > /dev/ttyS0) &
exec dbus-launch --exit-with-session startxfce4
