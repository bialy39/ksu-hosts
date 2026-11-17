#!/bin/sh
# build-hosts.sh -- generuje system/etc/hosts z surowej listy (StevenBlack i podobne)
# Uzycie: sh build-hosts.sh <surowa_lista> <wyjscie>
IN=${1:?podaj plik wejsciowy}
OUT=${2:?podaj plik wyjsciowy}

{
	printf '%s\n' \
		"# Systemless hosts (KernelSU) - lista blokujaca" \
		"# zrodlo: https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" \
		"127.0.0.1 localhost" \
		"::1 localhost ip6-localhost ip6-loopback" \
		"127.0.0.1 localhost.localdomain" \
		"255.255.255.255 broadcasthost" \
		""
	awk '
		{
			line = $0
			sub(/#.*/, "", line)          # obetnij komentarze (takze inline)
			n = split(line, f, /[[:space:]]+/)
			if (n < 2) next
			# wiodacy pusty element po split na poczatku linii
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
	' "$IN" | sort -u -k2,2
} >"$OUT"
