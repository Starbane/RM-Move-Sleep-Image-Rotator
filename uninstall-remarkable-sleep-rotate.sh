#!/bin/sh
set -eu
SERVICE="/etc/systemd/system/rotate-suspend-udev.service"
UDEV_RULE="/etc/udev/rules.d/99-remarkable-backlight-rotate.rules"
ROTATE="/home/root/bin/rotate_suspend.sh"
WRAPPER="/home/root/bin/rotate_wrapper.sh"
LOG="/home/root/rotate.log"
TARGET="/usr/share/remarkable/suspended.png"

echo "==> Disabling service/rules"
rm -f "$UDEV_RULE" 2>/dev/null || true
systemctl daemon-reload || true
udevadm control --reload || true

echo "==> Unmounting target if bound"
while grep -qE "[[:space:]]$TARGET[[:space:]]" /proc/self/mounts; do
  umount -l "$TARGET" || break
  sleep 0.1
done

echo "==> Removing scripts"
rm -f "$ROTATE" "$WRAPPER" 2>/dev/null || true

echo "==> Done. You may remove $LOG if you wish."
