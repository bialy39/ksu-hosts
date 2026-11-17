#!/bin/sh
# run-tests.sh -- testy lokalne logiki modulu (bez roota, z falszywym mount)
# Uruchomienie:  busybox ash tests/run-tests.sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BB=${BB:-}
if [ -z "$BB" ]; then
	if command -v busybox >/dev/null 2>&1; then BB=busybox; else BB=sh; fi
fi
# SH: uruchamia skrypt w ash busyboxa (jak na urzadzeniu); bez busyboxa - lokalny sh
SH() { if [ "$BB" = sh ]; then sh "$@"; else "$BB" ash "$@"; fi; }
FAILS=0
PASSES=0

ok()  { PASSES=$((PASSES+1)); echo "PASS  $*"; }
bad() { FAILS=$((FAILS+1));  echo "FAIL  $*"; }
# check <kod> <opis>  -- oczekuje kodu 0
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }
# no <kod> <opis>     -- oczekuje kodu != 0
no() { if [ "$1" != 0 ]; then ok "$2"; else bad "$2"; fi; }

TMP=$(mktemp -d /tmp/ksu-hosts-tests.XXXXXX) || exit 1
trap 'rm -rf "$TMP"' EXIT

# ---------- 1. skladnia (busybox ash = ten sam shell co na urzadzeniu) ----------
for f in "$ROOT"/*.sh; do
	if SH -n "$f" 2>"$TMP/err"; then
		if [ -s "$TMP/err" ]; then cat "$TMP/err"; bad "skladnia: $(basename "$f")"; else ok "skladnia: $(basename "$f")"; fi
	else
		cat "$TMP/err"; bad "skladnia: $(basename "$f")"
	fi
done

# ---------- srodowisko testowe ----------
export MOUNT_LOG="$TMP/mount.log"
export PROC_MOUNTS="$TMP/mounts"
export HOSTS_WORK="$TMP/work"
: >"$MOUNT_LOG"
: >"$PROC_MOUNTS"

mkdir -p "$TMP/bin" "$TMP/mod/system/etc" "$TMP/target" "$TMP/work"

# Falszywy mount: FUNKCJA shell (dziala nawet gdy busybox ma wlaczony
# standalone shell i ignoruje PATH, jak Ubuntu busybox-static w CI)
# + skrypt w PATH dla procesow potomnych.
fake_mount() {
	echo "$*" >>"$MOUNT_LOG"
	case "$*" in *--bind*) [ "${FAIL_BIND:-0}" = 1 ] && return 32 ;; esac
	[ "${FAIL_ALL:-0}" = 1 ] && return 32
	return 0
}
mount() { fake_mount "$@"; }

cat >"$TMP/bin/mount" <<'EOS'
#!/bin/sh
echo "$*" >>"$MOUNT_LOG"
case "$*" in *--bind*) [ "${FAIL_BIND:-0}" = 1 ] && exit 32 ;; esac
[ "${FAIL_ALL:-0}" = 1 ] && exit 32
exit 0
EOS
chmod +x "$TMP/bin/mount"
printf '127.0.0.1 localhost\n' >"$TMP/mod/system/etc/hosts"
printf 'placeholder\n' >"$TMP/target/hosts"
cp "$ROOT/common.sh" "$TMP/mod/common.sh"

export MODDIR="$TMP/mod"
export HOSTS_TARGET="$TMP/target/hosts"
export HOSTS_SRC="$TMP/mod/system/etc/hosts"
export PATH="$TMP/bin:$PATH"

# apply_hosts w podshellu: dziedziczy funkcje i zmienne, wiec fake mount dziala
run_apply() { ( . "$MODDIR/common.sh"; apply_hosts; echo "rc=$?" ); }

# ---------- 2. bind mount dziala ----------
: >"$MOUNT_LOG"; : >"$TMP/work/apply.log"
out=$(run_apply 2>&1); rc=$?
[ "$out" = "rc=0" ]; check $? "apply_hosts: rc=0 przy dzialajacym bind"
grep -q -- "--bind $TMP/mod/system/etc/hosts $TMP/target/hosts" "$MOUNT_LOG"; check $? "apply_hosts: bind na wlasciwych sciezkach"
grep -q "OK bind" "$TMP/work/apply.log"; check $? "apply_hosts: wpis OK bind w logu"

# ---------- 3. bind pada -> overlay ----------
: >"$MOUNT_LOG"; : >"$TMP/work/apply.log"
out=$(FAIL_BIND=1 run_apply 2>&1)
[ "$out" = "rc=0" ]; check $? "apply_hosts: rc=0 gdy bind pada, overlay dziala"
grep -q -- "-t overlay" "$MOUNT_LOG"; check $? "apply_hosts: fallback uzywa mount -t overlay"
grep -q -- "upperdir=$TMP/mod/system/etc" "$MOUNT_LOG"; check $? "apply_hosts: overlay upperdir w katalogu modulu"
grep -q -- "workdir=$TMP/mod/worker" "$MOUNT_LOG"; check $? "apply_hosts: overlay workdir ustawiony"
[ -d "$TMP/mod/worker" ]; check $? "apply_hosts: utworzono katalog worker"

# ---------- 4. wszystko pada -> rc=1 ----------
: >"$MOUNT_LOG"; : >"$TMP/work/apply.log"
out=$(FAIL_BIND=1 FAIL_ALL=1 run_apply 2>&1)
[ "$out" = "rc=1" ]; check $? "apply_hosts: rc=1 gdy bind i overlay padaja"
grep -q "ERROR" "$TMP/work/apply.log"; check $? "apply_hosts: blad trafia do logu"

# ---------- 5. juz podmontowane (nasz plik) -> brak montowania ----------
: >"$MOUNT_LOG"; : >"$TMP/work/apply.log"
cp -f "$HOSTS_SRC" "$HOSTS_TARGET"
printf '/data/adb/modules/ksu-hosts/system/etc/hosts %s ext4 rw 0 0\n' "$HOSTS_TARGET" >"$PROC_MOUNTS"
out=$(run_apply 2>&1)
[ "$out" = "rc=0" ]; check $? "apply_hosts: rc=0 gdy juz podmontowane"
[ -s "$MOUNT_LOG" ]; no $? "apply_hosts: brak ponownego montowania"
grep -q "juz podmontowany" "$TMP/work/apply.log"; check $? "apply_hosts: log potwierdza stan podmontowania"
: >"$PROC_MOUNTS"

# ---------- 5b. podmontowany jest INNY plik -> montujemy na wierzch ----------
: >"$MOUNT_LOG"; : >"$TMP/work/apply.log"
printf 'cos innego\n' >"$HOSTS_TARGET"
printf 'inny /somewhere/other/hosts %s ext4 rw 0 0\n' "$HOSTS_TARGET" >"$PROC_MOUNTS"
out=$(run_apply 2>&1)
[ "$out" = "rc=0" ]; check $? "apply_hosts: rc=0 gdy wisi obcy plik"
grep -q -- "--bind" "$MOUNT_LOG"; check $? "apply_hosts: obcy plik przykryty naszym bindem"
grep -q "wisi inny plik" "$TMP/work/apply.log"; check $? "apply_hosts: log informuje o obcym pliku"
: >"$PROC_MOUNTS"

# ---------- 5c. brak pliku docelowego -> jasny blad ----------
: >"$MOUNT_LOG"; : >"$TMP/work/apply.log"
out=$(HOSTS_TARGET="$TMP/nie-ma-takiego/hosts" run_apply 2>&1)
[ "$out" = "rc=1" ]; check $? "apply_hosts: rc=1 gdy brak pliku docelowego"
grep -q "nieoczekiwany uklad" "$TMP/work/apply.log"; check $? "apply_hosts: czytelny komunikat o brakujacym pliku"

# ---------- 6. overlay na katalogu nadrzednym wykryty ----------
out=$(SH -c '. "$MODDIR/common.sh"; printf "overlay %s overlay rw 0 0\n" "$TARGET_DIR" >"$PROC_MOUNTS"; is_mounted; echo "rc=$?"' 2>&1)
[ "$out" = "rc=0" ]; check $? "is_mounted: wykrywa overlay na katalogu nadrzednym"
: >"$PROC_MOUNTS"

# ---------- 7. normalizacja listy w update_hosts.sh ----------
SAMPLE="$TMP/sample.txt"
{
	echo "# komentarz naglowkowy"
	echo "0.0.0.0 #: smieciowa linia"
	echo "0.0.0.0 -"
	echo "0.0.0.0 0.0.0.0"
	echo "0.0.0.0 ads.example.com # inline comment"
	echo "127.0.0.1 tracker.example.net"
	echo "0.0.0.0 mail.example.org extra"
	echo "10.1.2.3 nieblokowane.example.com"
	echo "0.0.0.0 localhost"
	echo "0.0.0.0 UPPER.Example.COM"
	i=1; while [ $i -le 150 ]; do echo "0.0.0.0 d$i.test-domain.example"; i=$((i+1)); done
} >"$SAMPLE"

H="$TMP/mod/system/etc/hosts"
out=$(SH "$ROOT/update_hosts.sh" "$SAMPLE" 2>&1); rc=$?
[ $rc = 0 ]; check $? "update_hosts: rc=0 dla listy lokalnej"
grep -q "ads.example.com" "$H"; check $? "update_hosts: wpis z listy obecny (inline comment obcieta)"
grep -q "tracker.example.net" "$H"; check $? "update_hosts: 127.0.0.1 tez blokowany"
grep -q "mail.example.org" "$H"; check $? "update_hosts: wiele domen w linii rozbite"
grep -q " nieblokowane.example.com" "$H"; no $? "update_hosts: obcy IP odrzucony"
grep -qx "0.0.0.0 localhost" "$H"; no $? "update_hosts: localhost nie jest blokowany"
grep -q "upper.example.com" "$H"; check $? "update_hosts: domeny lowercase"
grep -q "0.0.0.0 #" "$H"; no $? "update_hosts: smieciowe linie odrzucone"
grep -qx "0.0.0.0 0.0.0.0" "$H"; no $? "update_hosts: artefakt 0.0.0.0 odrzucony"
n=$(grep -c '^0\.0\.0\.0 ' "$H"); [ "$n" = 154 ]; check $? "update_hosts: 154 wpisy (150 + 4), jest $n"
grep -qx "127.0.0.1 localhost" "$H"; check $? "update_hosts: naglowek localhost zachowany"
cmp -s "$H" "$TMP/work/hosts"; check $? "update_hosts: kopia w katalogu roboczym"

# ---------- 8. uszkodzona lista nie nadpisuje starej ----------
echo "0.0.0.0 tylko-jeden.example.com" >"$TMP/broken.txt"
before=$(md5sum "$H" | cut -d' ' -f1)
out=$(SH "$ROOT/update_hosts.sh" "$TMP/broken.txt" 2>&1); rc=$?
[ $rc = 1 ]; check $? "update_hosts: rc=1 dla listy < 100 wpisow"
after=$(md5sum "$H" | cut -d' ' -f1)
[ "$before" = "$after" ]; check $? "update_hosts: stara lista nietknieta po bledzie"

# ---------- 9. dolaczona lista hosts ----------
DEF="$ROOT/system/etc/hosts"
[ -s "$DEF" ]; check $? "system/etc/hosts: plik istnieje i nie jest pusty"
n=$(grep -c '^0\.0\.0\.0 ' "$DEF")
[ "${n:-0}" -gt 50000 ]; check $? "system/etc/hosts: >50k wpisow (jest $n)"
grep -qx "127.0.0.1 localhost" "$DEF"; check $? "system/etc/hosts: wpis localhost"
bad_lines=$(grep -vc '^#\|^$\|^127\.0\.0\.1 \|^::1 \|^255\.255\.255\.255 \|^0\.0\.0\.0 ' "$DEF")
[ "$bad_lines" = 0 ]; check $? "system/etc/hosts: tylko dozwolone formaty linii (dziwnych: $bad_lines)"
dups=$(awk '!/^#/ && NF>1 {print $2}' "$DEF" | sort | uniq -d | grep -vx localhost | wc -l)
[ "$dups" = 0 ]; check $? "system/etc/hosts: brak duplikatow domen ($dups)"
if grep -q "$(printf '\r')" "$DEF"; then bad "system/etc/hosts: konce linii CRLF"; else ok "system/etc/hosts: konce linii LF"; fi
if grep -q '^0\.0\.0\.0 [0-9.]*$' "$DEF"; then bad "system/etc/hosts: blokada golego IP"; else ok "system/etc/hosts: brak blokad golych IP"; fi

# ---------- 10. module.prop ----------
prop() { grep -m1 "^$1=" "$ROOT/module.prop" | cut -d= -f2-; }
id=$(prop id)
[ -n "$id" ]; check $? "module.prop: id ustawione"
printf '%s' "$id" | grep -q '^[a-zA-Z][a-zA-Z0-9._-]*$'; check $? "module.prop: id zgodne z regexem KSU ($id)"
case "$(prop versionCode)" in ''|*[!0-9]*) bad "module.prop: versionCode nie jest liczba" ;; *) ok "module.prop: versionCode liczba" ;; esac
for k in id name version versionCode author description; do
	[ -n "$(prop "$k")" ]; check $? "module.prop: pole $k niepuste"
done
grep -q "$(printf '\r')" "$ROOT/module.prop"; no $? "module.prop: konce linii LF"

echo
echo "================================"
echo "PASS: $PASSES   FAIL: $FAILS"
[ "$FAILS" = 0 ] || exit 1
