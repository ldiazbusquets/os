# OS: an Arch Linux desktop in the browser

A full Arch Linux 32 (i686) system with the XFCE desktop, running in the browser: https://ldiazbusquets.github.io/os/
The fast console-only version is at https://ldiazbusquets.github.io/linux/.

## How it is built

`.github/workflows/pages.yml` runs on every push:

1. `build/build-arch.sh` starts an `archlinux` container and runs `build/arch/make-root.sh`, which uses `pacstrap`
   against the [Arch Linux 32](https://archlinux32.org/) repositories to install the base system, Xorg (fbdev driver
   on the emulator's Bochs display) and XFCE, adds a mkinitcpio hook that mounts the root filesystem from v86's 9p
   share, and sets up the `arch` user, autologin straight into the desktop and a dark theme (`build/arch/rootfs`).
2. v86's `fs2json.py` and `copy-to-sha256.py` turn the root filesystem into `arch/fs.json` plus content-addressed,
   zstd-compressed files in `arch/flat/`, fetched on demand by the browser.
3. `build/state.mjs` boots it once in Node and saves `arch/state.bin.zst` once XFCE is running.
4. `build/test-page.mjs` opens the page in headless Chromium, checks the screen, opens a window, saves and restores.
5. The built image is kept in the `desktop-image` release and reused, so saved machines keep restoring. To update
   packages, run the workflow by hand with "rebuild" ticked (this resets saves).

## Licences

- Emulator: [v86](https://github.com/copy/v86) (BSD-2-Clause), from the `v86` npm package 0.5.473.
- BIOS: SeaBIOS and the VGA BIOS from the v86 repository (LGPL-3.0, `v86/LICENSE-seabios.txt`).
- Arch Linux 32 and XFCE packages: each under its own licence, sources from the Arch Linux 32 project.
  Not affiliated with Arch Linux.
- Wallpaper and icons: made for this project.
