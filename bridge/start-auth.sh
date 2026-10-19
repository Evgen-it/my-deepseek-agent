#!/bin/bash
set -e

rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

# Убираем шум от Openbox (не критично, просто чище логи)
mkdir -p /var/lib/openbox
touch /var/lib/openbox/debian-menu.xml

Xvfb :99 -screen 0 ${RESOLUTION} -ac &
sleep 2

# Openbox — минимальный оконный менеджер
openbox &
sleep 1

x11vnc -display :99 -forever -shared -nopw -rfbport 5900 -quiet &
websockify --web /usr/share/novnc/ 6080 localhost:5900 &
sleep 1

echo "=== VNC ready: http://localhost:6080/vnc.html ==="
echo "=== Waiting for DeepSeek sign-in... ==="

# КЛЮЧЕВОЕ: exec в foreground. Python сам откроет браузер и будет ждать логин.
# Когда логин завершится — контейнер выйдет с кодом 0.
exec python -m deepseek.auth