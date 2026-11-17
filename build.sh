#!/bin/sh
# build.sh -- pakuje modul do dist/ksu-hosts-<wersja>.zip (pliki na poziomie root zipa)
set -eu
cd "$(dirname "$0")"

VER=$(grep -m1 '^version=' module.prop | cut -d= -f2)
mkdir -p dist
OUT="dist/ksu-hosts-${VER}.zip"
FILES="module.prop common.sh customize.sh post-fs-data.sh post-mount.sh service.sh action.sh update_hosts.sh uninstall.sh README.md LICENSE system"

rm -f "$OUT"
chmod 0755 ./*.sh
chmod 0644 module.prop README.md LICENSE system/etc/hosts
zip -q -r -X "$OUT" $FILES
echo "zbudowano: $(pwd)/$OUT"
unzip -l "$OUT"
