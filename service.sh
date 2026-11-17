#!/system/bin/sh
# service.sh -- late_start service, ostatnia szansa na podmontowanie hosts
MODDIR=${0%/*}
. "$MODDIR/common.sh"

log "service: sprawdzam hosts"
apply_hosts
sync_mirror
exit 0
