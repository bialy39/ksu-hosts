#!/system/bin/sh
# post-fs-data.sh -- najwczesniejszy etap, zanim wystartuje zygote/apki
MODDIR=${0%/*}
. "$MODDIR/common.sh"

log "post-fs-data: start (KSU=${KSU:-?})"
apply_hosts
sync_mirror
exit 0
