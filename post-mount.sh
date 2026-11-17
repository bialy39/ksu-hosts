#!/system/bin/sh
# post-mount.sh -- po zamontowaniu modulow przez KSU/metamodul.
# Gdyby KSU nadpisal nasz bind wlasnym montazem /system, przywracamy go tutaj.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

log "post-mount: sprawdzam hosts"
apply_hosts
sync_mirror
exit 0
