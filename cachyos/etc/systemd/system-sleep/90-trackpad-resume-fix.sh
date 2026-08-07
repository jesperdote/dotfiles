#!/usr/bin/env bash
# Fixes two compounding bugs that leave the built-in touchpad and TrackPoint
# dead after resume on this ThinkPad T14 Gen2 (see README.md for full diagnosis):
#
# 1. The Synaptics touchpad's RMI4/SMBus transport doesn't always re-init after
#    suspend - the input device stays enumerated but delivers zero events/IRQs.
#    Fixed by rebinding the psmouse driver on serio1 (the i8042 AUX port), which
#    forces it to redo the "set up SMBus access" handshake.
# 2. Toshy's xwaykeyz remapper exclusively grabs input devices, including the
#    touchpad/TrackPoint. If it re-grabs mid-resume, before fix #1 above has run,
#    the grab can end up stale/broken (BrokenPipeError in its logs) and silently
#    blackholes input to everyone, including the compositor. Only killing and
#    restarting it clears this - fixed by restarting toshy-config.service.
#
# systemd-sleep hooks run as root with $1=pre/post, $2=suspend/hibernate/etc.
set -eu

[[ "${1:-}" == "post" ]] || exit 0
case "${2:-}" in
    suspend | suspend-then-hibernate) ;;
    *) exit 0 ;;
esac

# Give the SMBus controller a moment to finish resuming before poking it.
sleep 2

echo -n "serio1" >/sys/bus/serio/drivers/psmouse/unbind 2>/dev/null || true
echo -n "serio1" >/sys/bus/serio/drivers/psmouse/bind 2>/dev/null || true

TARGET_USER="$(loginctl list-sessions --no-legend | awk '$4 == "seat0" { print $3; exit }')"
if [[ -n "$TARGET_USER" ]]; then
    USER_ID="$(id -u "$TARGET_USER")"
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$USER_ID" \
        systemctl --user restart toshy-config.service 2>/dev/null || true
fi
