#!/usr/bin/env bash
# Runs inside a privileged x86_64 archlinux container. Installs Arch Linux 32 (i686)
# into /out/root with pacstrap, with an XFCE desktop, configured to boot from v86's 9p filesystem.
set -euo pipefail
B=/build; R=/out/root
pacman -Sy --noconfirm --needed arch-install-scripts curl >/dev/null

MIRRORS=(https://mirror.yandex.ru/archlinux32 https://mirror.datacenter.by/pub/archlinux32 https://mirror.archlinux32.org https://de.mirror.archlinux32.org)
OK=()
for m in "${MIRRORS[@]}"; do curl -fsI --max-time 20 "$m/i686/core/core.db" >/dev/null && OK+=("$m") && echo "mirror ok: $m" || echo "mirror down: $m"; done
[ ${#OK[@]} -gt 0 ] || { echo "no Arch Linux 32 mirror reachable"; exit 1; }
REPOS=(core extra)
curl -fsI --max-time 20 "${OK[0]}/i686/community/community.db" >/dev/null && REPOS+=(community)
echo "repos: ${REPOS[*]}"

mkdir -p "$R/etc/pacman.d"
: > /tmp/mirrorlist32
for m in "${OK[@]}"; do echo "Server = $m/\$arch/\$repo" >> /tmp/mirrorlist32; done
conf() { # $1 = SigLevel, $2 = mirrorlist path
  printf '[options]\nArchitecture = i686\nHoldPkg = pacman glibc\nColor\nILoveCandy\nParallelDownloads = 6\nSigLevel = %s\nLocalFileSigLevel = Optional\n' "$1"
  for r in "${REPOS[@]}"; do printf '\n[%s]\nInclude = %s\n' "$r" "$2"; done
}
conf Never /tmp/mirrorlist32 > /tmp/pacman32.conf

# Our boot hook, initramfs config and preset go in first so the kernel install uses them.
install -Dm644 "$B/9p_root.hook" "$R/etc/initcpio/hooks/9p_root"
install -Dm644 "$B/9p_root.install" "$R/etc/initcpio/install/9p_root"
mkdir -p "$R/etc/mkinitcpio.d"
printf 'MODULES=(virtio_pci virtio_net 9p 9pnet 9pnet_virtio)\nBINARIES=()\nFILES=()\nHOOKS=(base udev modconf keyboard 9p_root)\nCOMPRESSION="zstd"\n' > "$R/etc/mkinitcpio.conf"
printf "PRESETS=('default')\nALL_kver='/boot/vmlinuz-linux'\ndefault_image='/boot/initramfs-linux.img'\n" > "$R/etc/mkinitcpio.d/linux.preset"

pacstrap -C /tmp/pacman32.conf -M -G "$R" base linux mkinitcpio sudo nano vim less man-db man-pages bash-completion htop python git tree wget curl which inetutils dhcpcd iproute2 archlinux32-keyring \
  xorg-server xorg-xinit xorg-xset xorg-xrandr xorg-xdpyinfo xf86-video-fbdev xf86-input-libinput xfce4 mousepad ristretto ttf-dejavu adwaita-icon-theme
cp /tmp/pacman32.conf "$R/etc/pacman.conf"; cp /tmp/mirrorlist32 "$R/etc/pacman.d/mirrorlist"
sed -i 's#Include = /tmp/mirrorlist32#Include = /etc/pacman.d/mirrorlist#' "$R/etc/pacman.conf"
for p in fastfetch xfce4-taskmanager xfce4-screenshooter galculator gnome-themes-extra netsurf dillo unzip zip cowsay; do arch-chroot "$R" pacman -S --noconfirm --needed "$p" >/dev/null 2>&1 && echo "added $p" || echo "skipped $p"; done

# Arch Linux 32 published pango/cairo built against fontconfig 2.18 but its repos still carry 2.14,
# which breaks every GTK app (undefined symbol FcConfigSetDefaultSubstitute). Take the matching
# fontconfig build from the Arch Linux 32 archive.
AR=https://archive.archlinux32.org/packages/f/fontconfig/
FC=$(curl -fsSL --max-time 30 "$AR" | grep -oE 'fontconfig-2:[0-9.]+-[0-9.]+-i686\.pkg\.tar\.zst' | sort -uV | tail -1 || true)
if [ -n "$FC" ]; then
  echo "fontconfig from archive: $FC"
  curl -fsSL -o "$R/root/fc.pkg.tar.zst" "$AR${FC//:/%3A}" && arch-chroot "$R" pacman -U --noconfirm /root/fc.pkg.tar.zst; rm -f "$R/root/fc.pkg.tar.zst"
else echo "::warning::could not find fontconfig in the Arch Linux 32 archive"; fi

# Catch library mismatches at build time instead of as a blank screen.
arch-chroot "$R" bash -c 'for b in /usr/bin/xfce4-session /usr/bin/xfwm4 /usr/bin/xfce4-panel /usr/bin/xfdesktop /usr/bin/thunar /usr/bin/xfce4-terminal /usr/bin/mousepad /usr/bin/ristretto /usr/bin/xfce4-appfinder /usr/bin/xfsettingsd /usr/bin/dillo /usr/bin/galculator /usr/lib/libgtk-3.so.0 /usr/lib/libpangoft2-1.0.so.0 /usr/lib/libcairo.so.2; do [ -e "$b" ] || { echo "abi: missing $b"; continue; }; u=$(ldd -r "$b" 2>&1 | grep -E "undefined symbol|not found" | head -3); [ -n "$u" ] && echo "abi: $b: $u" || echo "abi: ok $b"; done'

# overlay files and system setup
cp -a --no-preserve=ownership "$B/rootfs/." "$R/"
chown -R root:root "$R/etc/sudoers.d" "$R/usr/local/bin" "$R/etc/systemd/system" "$R/etc/X11" "$R/etc/modules-load.d" "$R/etc/locale.conf" "$R/etc/hostname" "$R/usr/share/backgrounds/ldb"
arch-chroot "$R" bash -euxc '
  chmod 0440 /etc/sudoers.d/wheel; chmod +x /usr/local/bin/*
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen; locale-gen
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
  useradd -m -G wheel,video,input,audio,uucp -s /bin/bash arch; echo arch:arch | chpasswd; echo root:root | chpasswd
  cp -a /etc/skel-desktop/. /home/arch/; rm -rf /etc/skel-desktop
  mkdir -p /home/arch/.config/xfce4/xfconf/xfce-perchannel-xml /home/arch/Desktop /home/arch/Documents /home/arch/Downloads
  cp /etc/xdg/xfce4/panel/default.xml /home/arch/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
  cp /usr/share/applications/xfce4-terminal.desktop /home/arch/Desktop/ 2>/dev/null || true
  cp /usr/share/applications/thunar.desktop /home/arch/Desktop/ 2>/dev/null || true
  chmod +x /home/arch/Desktop/*.desktop 2>/dev/null || true
  chown -R arch:arch /home/arch
  systemd-machine-id-setup
  for u in systemd-firstboot.service ldconfig.service man-db.timer man-db.service shadow.timer systemd-tmpfiles-clean.timer archlinux-keyring-wkd-sync.timer systemd-timesyncd.service systemd-networkd-wait-online.service systemd-homed.service systemd-userdbd.socket; do systemctl mask "$u" >/dev/null 2>&1 || true; done
  rm -f /boot/initramfs-linux-fallback.img
  mkinitcpio -P
  ls -la /boot
'

# Package signatures: use them if the keyring works, otherwise fall back so pacman is usable.
SIG="Required DatabaseOptional"
conf "$SIG" /etc/pacman.d/mirrorlist > "$R/etc/pacman.conf"
if arch-chroot "$R" bash -c 'pacman-key --init && (pacman-key --populate archlinux32 || pacman-key --populate) && pacman -Sy --noconfirm && pacman -S --noconfirm tree'; then
  echo "signatures: on, a verified reinstall worked"
else
  echo "::warning::Arch Linux 32 keyring check failed, pacman signature checking is off"
  conf Never /etc/pacman.d/mirrorlist > "$R/etc/pacman.conf"
fi
arch-chroot "$R" pacman -Sy --noconfirm >/dev/null || true   # fresh package lists for offline pacman -Ss

# smaller: drivers a virtual PC never needs, other languages, caches
K=$(ls "$R/usr/lib/modules" | head -1); M="$R/usr/lib/modules/$K/kernel"
rm -rf "$M"/drivers/gpu/drm/{amd,radeon,nouveau,i915,xe,gma500,mgag200,ast,vmwgfx,qxl,virtio,msm,etnaviv,lima,panfrost,panthor,vc4,v3d,tegra,imx,rockchip,sun4i,exynos,mediatek,meson,stm,tidss,omapdrm} "$M"/drivers/{media,infiniband,staging,scsi,bluetooth,iio,isdn,mtd,usb,hwmon,thunderbolt,firewire,nfc,hid} "$M"/drivers/net/{wireless,can,usb} "$M"/drivers/input/{joystick,touchscreen,tablet} "$M"/sound "$M"/net/{bluetooth,wireless,mac80211} 2>/dev/null || true
arch-chroot "$R" depmod -a "$K"
find "$R/usr/share/locale" -mindepth 1 -maxdepth 1 ! -name 'en*' ! -name 'locale.alias' -exec rm -rf {} +
rm -rf "$R"/usr/share/doc/* "$R/usr/share/gtk-doc" "$R"/var/cache/pacman/pkg/* "$R"/var/log/*.log
echo "root size: $(du -sh "$R" | cut -f1)"
