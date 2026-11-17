#!/system/bin/sh
# update_hosts.sh -- pobiera liste blokujaca i podmienia hosts w locie
# Uzycie:
#   sh /data/adb/modules/ksu-hosts/update_hosts.sh            (lista domyslna: StevenBlack)
#   sh /data/adb/modules/ksu-hosts/update_hosts.sh <url|sciezka>
# Zmiana dziala od razu, bez restartu.

MODDIR=${0%/*}
[ -f "$MODDIR/common.sh" ] || MODDIR=/data/adb/modules/ksu-hosts
. "$MODDIR/common.sh"

SRCURL=${1:-https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts}
WORK=${HOSTS_WORK:-/data/adb/systemless-hosts}
RAW="$WORK/hosts.raw"
NEW="$WORK/hosts.new"
mkdir -p "$WORK" 2>/dev/null

fetch() {
	if [ -f "$SRCURL" ]; then
		cp -f "$SRCURL" "$RAW"
		return $?
	fi
	busybox wget -q -O "$RAW" "$SRCURL" 2>/dev/null && return 0
	curl -fsSL -o "$RAW" "$SRCURL" 2>/dev/null && return 0
	wget -q -O "$RAW" "$SRCURL" 2>/dev/null && return 0
	return 1
}

echo "pobieram: $SRCURL"
if ! fetch; then
	echo "! pobranie nie powiodlo sie"
	exit 1
fi

{
	printf '%s\n' \
		"# Systemless hosts (KernelSU) - lista wygenerowana przez update_hosts.sh" \
		"# zrodlo: $SRCURL" \
		"127.0.0.1 localhost" \
		"::1 localhost ip6-localhost ip6-loopback" \
		"127.0.0.1 localhost.localdomain" \
		"255.255.255.255 broadcasthost" \
		""
	awk '
		{
			line = $0
			sub(/#.*/, "", line)
			n = split(line, f, /[[:space:]]+/)
			if (n < 2) next
			start = 1
			if (f[1] == "") start = 2
			ip = f[start]
			if (ip != "0.0.0.0" && ip != "127.0.0.1") next
			for (i = start + 1; i <= n; i++) {
				d = tolower(f[i])
				if (d !~ /^[a-z0-9_]([a-z0-9_.-]*[a-z0-9_])?(\.[a-z0-9_]([a-z0-9_.-]*[a-z0-9_])?)+$/) continue
				if (d ~ /^[0-9.]+$/) continue
				if (d == "localhost.localdomain") continue
				print "0.0.0.0 " d
			}
		}
	' "$RAW" | sort -u -k2,2
} >"$NEW" 2>/dev/null

ents=$(grep -c '^0\.0\.0\.0 ' "$NEW" 2>/dev/null)
if [ "${ents:-0}" -lt 100 ]; then
	echo "! lista wyglada na uszkodzona (${ents:-0} wpisow), zostawiam stara"
	rm -f "$NEW"
	exit 1
fi

# Zapis w miejscu (truncate), zeby bind mount na /system/etc/hosts
# dalej wskazywal ten sam plik i zmiana byla widoczna natychmiast.
if is_mounted; then
	cat "$NEW" >"$TARGET" || { echo "! zapis do $TARGET nie powiodl sie"; exit 1; }
else
	cat "$NEW" >"$SRC" || { echo "! zapis do $SRC nie powiodl sie"; exit 1; }
	fix_attrs
	apply_hosts
fi

cp -f "$NEW" "$WORK/hosts" 2>/dev/null
rm -f "$NEW" "$RAW"

echo "gotowe: $ents blokowanych domen"
echo "aktywny plik: $TARGET"
