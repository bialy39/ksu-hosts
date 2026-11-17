#!/system/bin/sh
# uninstall.sh -- odmontowanie hosts przy usuwaniu modulu
TARGET=/system/etc/hosts
[ -f "$TARGET" ] && umount "$TARGET" 2>/dev/null
[ -f /system/etc/hosts ] && umount /system/etc 2>/dev/null
# kopia listy zostaje w /data/adb/systemless-hosts (przydatna przy powrocie do modulu)
exit 0
