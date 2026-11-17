#!/system/bin/sh
# customize.sh -- uruchamiany przez menedzer KernelSU przy instalacji modulu
PATH=/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk:$PATH

WORK=/data/adb/systemless-hosts
SRC="$MODPATH/system/etc/hosts"

command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

ui_print "- Systemless Hosts (KernelSU)"
ui_print "- katalog modulu: $MODPATH"

mkdir -p "$MODPATH/system/etc" 2>/dev/null
mkdir -p "$WORK" 2>/dev/null

# Poprzednia lista (np. wygenerowana przez AdAway) ma pierwszenstwo nad
# lista domyslna dolaczona do zipa.
if [ -s "$WORK/hosts" ]; then
	ui_print "- przywracam poprzednia liste hosts z $WORK/hosts"
	cp -f "$WORK/hosts" "$SRC"
else
	ui_print "- instaluje domyslna liste blokujaca"
fi

if [ ! -s "$SRC" ]; then
	ui_print "! brak pliku hosts, przerywam"
	abort "nie moge utworzyc system/etc/hosts"
fi

chmod 0644 "$SRC" 2>/dev/null
chcon u:object_r:system_file:s0 "$SRC" 2>/dev/null || busybox chcon u:object_r:system_file:s0 "$SRC" 2>/dev/null

# Wlasne montowanie w post-fs-data / post-mount, wiec KSU nie ma montowac
# katalogu system (skip_mount).
mkdir -p "$MODPATH/worker" 2>/dev/null
chmod 0755 "$MODPATH"/*.sh 2>/dev/null
touch "$MODPATH/skip_mount"

ui_print "- wpisow w liscie: $(grep -c '^0\.0\.0\.0 ' "$SRC" 2>/dev/null)"
ui_print "- gotowe, zrestartuj urzadzenie"
