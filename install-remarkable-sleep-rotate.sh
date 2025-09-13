#!/bin/sh
# install-remarkable-sleep-rotate.sh
# reMarkable Paper Pro Move — event-driven (no polling) sleep image rotator
# Creates rotation scripts, udev+systemd wiring, and an uninstaller.
# Run as root on the device:  sh install-remarkable-sleep-rotate.sh

set -eu

IMAGEDIR="/home/root/images"
BINDIR="/home/root/bin"
LOG="/home/root/rotate.log"
TARGET="/usr/share/remarkable/suspended.png"

SERVICE="/etc/systemd/system/rotate-suspend-udev.service"
UDEV_RULE="/etc/udev/rules.d/99-remarkable-backlight-rotate.rules"
SLEEP_HOOK="/etc/systemd/system-sleep/rotate-suspend.sh" # we will REMOVE this if it exists

WRAPPER="$BINDIR/rotate_wrapper.sh"
ROTATE="$BINDIR/rotate_suspend.sh"
UNINSTALL="$BINDIR/uninstall-remarkable-sleep-rotate.sh"

BL="/sys/class/backlight/rm_frontlight/bl_power"

echo "==> Preparing directories"
mkdir -p "$IMAGEDIR" "$BINDIR" /etc/udev/rules.d /etc/systemd/system

# -------------------------------------------
# Rotation script (idempotent, no findmnt, uses /proc/self/mounts)
# Also guards against running during wake (frontlight on).
# -------------------------------------------
cat > "$ROTATE" << 'EOF'
#!/bin/sh
IMAGEDIR="/home/root/images"
TARGET="/usr/share/remarkable/suspended.png"
STATE="/home/root/.suspend_index"
LOG="/home/root/rotate.log"
LOCK="/run/rotate-suspend.lock"
BL="/sys/class/backlight/rm_frontlight/bl_power"

log(){ printf "[%s] %s\n" "$(date '+%F %T')" "$*" >> "$LOG"; }

# Guard: only rotate when frontlight is OFF (sleep). On many systems: 0=on, !=0=off
blv=$(cat "$BL" 2>/dev/null || echo 0)
if [ "$blv" -eq 0 ]; then
  log "Skip: rotate invoked but frontlight ON (bl_power=$blv)"
  exit 0
fi

# Simple lock to avoid overlap
mkdir "$LOCK" 2>/dev/null || { log "Skip: lock active"; exit 0; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# List PNGs (stable order)
FILES=$(ls "$IMAGEDIR"/*.png "$IMAGEDIR"/*.PNG 2>/dev/null | sort || true)
[ -z "$FILES" ] && { log "No PNGs in $IMAGEDIR"; exit 0; }

COUNT=$(printf "%s\n" "$FILES" | wc -l | tr -d ' ')
IDX=-1; [ -f "$STATE" ] && IDX=$(cat "$STATE" 2>/dev/null || echo -1)
NEXT=$(( (IDX + 1) % COUNT ))

# Select line NEXT
N=0; SEL=""
printf "%s\n" "$FILES" | while IFS= read -r line; do
  [ $N -eq $NEXT ] && { echo "$line"; exit 0; }
  N=$((N+1))
done > /tmp/.next_sleep_img
SEL=$(cat /tmp/.next_sleep_img 2>/dev/null); rm -f /tmp/.next_sleep_img
[ -z "$SEL" ] && { log "Failed to select image (NEXT=$NEXT)"; exit 1; }

# Current mount source (if any)
CUR=$(awk '$2=="/usr/share/remarkable/suspended.png"{print $1}' /proc/self/mounts | tail -n1)

# If the same source is already mounted, do nothing (idempotent)
if [ "x$CUR" = "x$SEL" ]; then
  echo "$NEXT" > "$STATE"
  log "Already mounted: '$SEL' -> '$TARGET' (IDX=$NEXT/$COUNT)"
  exit 0
fi

# Clean any previous binds on TARGET
while grep -qE "[[:space:]]$TARGET[[:space:]]" /proc/self/mounts; do
  umount -l "$TARGET" 2>>"$LOG" || break
  sleep 0.1
done

# Make sure source isn't a mountpoint by mistake
while grep -qE "[[:space:]]$SEL[[:space:]]" /proc/self/mounts; do
  umount -l "$SEL" 2>>"$LOG" || break
  sleep 0.1
done

# Bind mount and remount read-only (safety)
if mount --bind "$SEL" "$TARGET" 2>>"$LOG"; then
  mount -o remount,bind,ro "$TARGET" 2>>"$LOG" || true
  echo "$NEXT" > "$STATE"
  log "OK: mounted '$SEL' -> '$TARGET' (IDX=$NEXT/$COUNT)"
  exit 0
else
  log "ERROR: mount failed '$SEL' -> '$TARGET'"
  exit 1
fi
EOF
chmod +x "$ROTATE"

# -------------------------------------------
# Wrapper: edge detection (frontlight 0->1 only) + debounce
# -------------------------------------------
cat > "$WRAPPER" << 'EOF'
#!/bin/sh
LOG="/home/root/rotate.log"
ROT="/home/root/bin/rotate_suspend.sh"
BL="/sys/class/backlight/rm_frontlight/bl_power"
STAMP="/run/rotate-suspend.last"   # for debounce
STATE="/run/frontlight.last"       # 0=on, 1=off (normalized)
DEBOUNCE=10                        # seconds

ts(){ date +%s; }
log(){ printf "[%s] %s\n" "$(date '+%F %T')" "$*" >> "$LOG"; }

cur_raw=$(cat "$BL" 2>/dev/null || echo 0)
[ "$cur_raw" -eq 0 ] && cur=0 || cur=1
[ -f "$STATE" ] && last=$(cat "$STATE" 2>/dev/null) || last=0
echo "$cur" > "$STATE"

now=$(ts)
age=9999; [ -f "$STAMP" ] && age=$(( now - $(cat "$STAMP" 2>/dev/null || echo 0) ))

# Only run on the edge: 0 -> 1 (going to sleep)
if [ "$last" -eq 0 ] && [ "$cur" -eq 1 ]; then
  if [ "$age" -lt "$DEBOUNCE" ]; then
    log "Skip: edge 0->1 but debounce ($age<s)"
    exit 0
  fi
  echo "$now" > "$STAMP"
  log "Edge 0->1 (bl_power=$cur_raw) -> rotate"
  exec "$ROT"
else
  log "Skip: no sleep edge (last=$last cur=$cur bl_power=$cur_raw)"
  exit 0
fi
EOF
chmod +x "$WRAPPER"

# -------------------------------------------
# systemd oneshot service (triggered by udev)
# -------------------------------------------
cat > "$SERVICE" << EOF
[Unit]
Description=Rotate suspended.png on backlight change (udev, edge-triggered)
After=local-fs.target

[Service]
Type=oneshot
ExecStart=$WRAPPER
EOF

# -------------------------------------------
# udev rule to request the service (no direct RUN+=)
# -------------------------------------------
cat > "$UDEV_RULE" << EOF
SUBSYSTEM=="backlight", KERNEL=="rm_frontlight", ACTION=="change", \  TAG+="systemd", ENV{SYSTEMD_WANTS}="$(os.path.basename(SERVICE))"
EOF

echo "==> Removing legacy triggers (if any)"
# Remove any legacy system-sleep hook
rm -f "$SLEEP_HOOK" 2>/dev/null || true

# Remove old rules that directly RUN the rotate script
for f in /etc/udev/rules.d/*; do
  [ -f "$f" ] || continue
  if grep -qE 'rotate_suspend\.sh|RUN\+\=' "$f" 2>/dev/null; then
    echo "   - Removing legacy rule: $f"
    rm -f "$f" || true
  fi
done

echo "==> Enabling our udev+systemd wiring"
systemctl daemon-reload
udevadm control --reload

# -------------------------------------------
# One-time cleanup of any stacked mounts
# -------------------------------------------
echo "==> Cleaning any previous stacked binds on target"
while grep -qE "[[:space:]]$TARGET[[:space:]]" /proc/self/mounts; do
  umount -l "$TARGET" || break
  sleep 0.1
done

# Paranoid cleanup on sources (rare, but harmless)
for f in "$IMAGEDIR"/*.png "$IMAGEDIR"/*.PNG; do
  [ -e "$f" ] || continue
  while grep -qE "[[:space:]]$f[[:space:]]" /proc/self/mounts; do
    umount -l "$f" || break
    sleep 0.1
  done
done

# -------------------------------------------
# Uninstaller
# -------------------------------------------
cat > "$UNINSTALL" << EOF
#!/bin/sh
set -eu
SERVICE="$SERVICE"
UDEV_RULE="$UDEV_RULE"
ROTATE="$ROTATE"
WRAPPER="$WRAPPER"
LOG="$LOG"
TARGET="$TARGET"

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
EOF
chmod +x "$UNINSTALL"

# -------------------------------------------
# First-time dry run (if images exist)
# -------------------------------------------
echo "==> First-time dry run"
if ls "$IMAGEDIR"/*.png "$IMAGEDIR"/*.PNG >/dev/null 2>&1; then
  "$WRAPPER" || true
else
  echo "   - No PNGs in $IMAGEDIR yet. Copy images (954x1696 PNG) and it will rotate on next sleep."
fi

echo "==> Sanity checks"
echo " - Service file: $SERVICE"
echo " - Udev rule:    $UDEV_RULE"
echo " - Scripts:      $ROTATE, $WRAPPER"
echo " - Images dir:   $IMAGEDIR"
echo " - Log:          $LOG"

echo "==> Done. Put PNGs (954x1696) into $IMAGEDIR. Then press power to sleep; one image will rotate per sleep."
