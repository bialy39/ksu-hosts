#!/system/bin/sh
# action.sh -- przycisk "Action" w menedzerze KernelSU: status + ponowne podpiecie
MODDIR=${0%/*}
. "$MODDIR/common.sh"

echo "=== Systemless Hosts (KernelSU) ==="

if apply_hosts; then
	:
else
	echo "! nie udalo sie podmienic /system/etc/hosts (szczegoly: $LOG)"
fi

if is_mounted; then
	echo "montowanie: OK"
else
	echo "montowanie: BRAK"
fi

if [ -f "$SRC" ]; then
	ents=$(grep -c '^0\.0\.0\.0 ' "$SRC" 2>/dev/null)
	size=$(ls -l "$SRC" 2>/dev/null | awk '{print $5}')
	echo "blokowanych domen: ${ents:-0}"
	echo "rozmiar pliku: ${size:-0} B"
fi

echo "target: $TARGET"
echo "zrodlo: $SRC"
