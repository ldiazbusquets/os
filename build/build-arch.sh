#!/usr/bin/env bash
# Builds Arch Linux 32 (i686) as a v86 9p filesystem: OUT/fs.json + OUT/flat/*.bin.zst
# Runs on GitHub Actions (needs internet, Docker and sudo). Usage: build/build-arch.sh OUT
set -euo pipefail
OUT="$(realpath -m "${1:?output dir}")"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"; cd "$WORK"

mkdir -p out
docker run --rm --privileged -v "$HERE/arch:/build:ro" -v "$WORK/out:/out" archlinux:latest bash /build/make-root.sh
sudo mv out/root fs

# network files the emulator setup expects
echo arch | sudo tee fs/etc/hostname >/dev/null
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 arch\n' | sudo tee fs/etc/hosts >/dev/null
sudo rm -f fs/etc/resolv.conf
echo 'nameserver 192.168.86.1' | sudo tee fs/etc/resolv.conf >/dev/null
ls -la fs/boot
sudo du -sh fs

git clone -q --depth 1 https://github.com/copy/v86 v86src
TMP="$OUT.tmp"; rm -rf "$TMP"; mkdir -p "$TMP/flat"
sudo python3 v86src/tools/fs2json.py --zstd --out "$TMP/fs.json" fs
sed -i "s/level=19/level=9/g" v86src/tools/copy-to-sha256.py
sudo python3 v86src/tools/copy-to-sha256.py --zstd fs "$TMP/flat"
sudo chown -R "$(id -u):$(id -g)" "$TMP"
echo "{\"built\":\"$(date -u +%Y-%m-%d)\",\"base\":\"Arch Linux 32 (i686)\"}" > "$TMP/build.json"
du -sh "$TMP"; ls "$TMP/flat" | wc -l
rm -rf "$OUT"; mv "$TMP" "$OUT"
