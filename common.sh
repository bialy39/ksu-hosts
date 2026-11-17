#!/system/bin/sh
# common.sh -- wspolne funkcje modulu ksu-hosts (sourced przez skrypty startowe)
# Wymaga ustawionego MODDIR przez skrypt wywolujacy.

TARGET=${HOSTS_TARGET:-/system/etc/hosts}
TARGET_DIR=${TARGET%/*}
PROC_MOUNTS=${PROC_MOUNTS:-/proc/mounts}
SRC=${HOSTS_SRC:-$MODDIR/system/etc/hosts}
WORK=${HOSTS_WORK:-/data/adb/systemless-hosts}
LOG="$WORK/apply.log"

log() {
	mkdir -p "$WORK" 2>/dev/null
	printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >>"$LOG" 2>/dev/null
	if [ -f "$LOG" ] && [ "$(wc -l <"$LOG" 2>/dev/null)" -gt 300 ] 2>/dev/null; then
		tail -n 150 "$LOG" >"$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null
	fi
}

# Ustawia prawa i kontekst SELinux pliku hosts (kontekst system_file jest
# konieczny, zeby apki w domenie untrusted_app mogly go czytac).
fix_attrs() {
	[ -f "$SRC" ] || return 1
	chmod 0644 "$SRC" 2>/dev/null
	chcon u:object_r:system_file:s0 "$SRC" 2>/dev/null ||
		busybox chcon u:object_r:system_file:s0 "$SRC" 2>/dev/null ||
		log "WARN: chcon nie powiodl sie (kontekst pliku hosts moze byc inny)"
	return 0
}

# Czy hosts jest juz podmontowany (bind pliku albo overlay na /system/etc)?
is_mounted() {
	grep -qs " $TARGET " "$PROC_MOUNTS" && return 0
	grep -qs " $TARGET_DIR " "$PROC_MOUNTS" && return 0
	return 1
}

# Podmienia /system/etc/hosts na plik z katalogu modulu.
# 1) bind mount pliku -> zapisy ida wprost do modulu (przetrwa restart)
# 2) fallback: overlayfs na /system/etc (gdy bind jest zablokowany)
apply_hosts() {
	fix_attrs || {
		log "ERROR: brak pliku $SRC"
		return 1
	}
	[ -e "$TARGET" ] || {
		log "ERROR: brak $TARGET - nieoczekiwany uklad partycji system"
		return 1
	}

	if is_mounted; then
		# jesli wisi juz nasz plik (bind/overlay), tresc jest identyczna
		if cmp -s "$SRC" "$TARGET" 2>/dev/null; then
			log "hosts juz podmontowany, nic nie robie"
			return 0
		fi
		log "na $TARGET wisi inny plik - montuje nasz na wierzch"
	fi

	if mount --bind "$SRC" "$TARGET" 2>>"$LOG"; then
		log "OK bind: $SRC -> $TARGET"
		return 0
	fi
	log "bind nie wyszedl, probuje overlayfs"

	mkdir -p "$MODDIR/worker" 2>/dev/null
	if mount -t overlay -o "lowerdir=$TARGET_DIR,upperdir=$MODDIR/system/etc,workdir=$MODDIR/worker" KSU "$TARGET_DIR" 2>>"$LOG"; then
		log "OK overlay: $TARGET_DIR"
		return 0
	fi

	log "ERROR: nie udalo sie podmienic hosts (bind i overlay padly)"
	return 1
}

# Kopia zapasowa listy poza katalogiem modulu, zeby przetrwala reinstalacje.
sync_mirror() {
	mkdir -p "$WORK" 2>/dev/null
	[ -f "$SRC" ] || return 1
	if ! cmp -s "$SRC" "$WORK/hosts" 2>/dev/null; then
		cp -f "$SRC" "$WORK/hosts" 2>/dev/null && log "mirror zaktualizowany"
	fi
	return 0
}
