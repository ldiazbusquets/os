// Boots the built Arch desktop once in Node and saves a snapshot once XFCE is on screen,
// so the page can resume a running desktop instead of booting from scratch.
// Usage: node build/state.mjs ARCH_DIR V86_DIR   (writes ARCH_DIR/state.bin.zst)
import { V86 } from "v86";
import fs from "node:fs";
import path from "node:path";
import url from "node:url";
import { execFileSync } from "node:child_process";

const [dir, biosDir] = process.argv.slice(2).map(p => path.resolve(p));
const wasm = path.join(path.dirname(url.fileURLToPath(import.meta.resolve("v86"))), "v86.wasm");
// Keep in sync with HW in index.html: a snapshot only restores on identical hardware.
const emu = new V86({
  wasm_path: wasm,
  bios: { url: path.join(biosDir, "seabios.bin") },
  vga_bios: { url: path.join(biosDir, "vgabios.bin") },
  memory_size: 768 * 1024 * 1024,
  vga_memory_size: 8 * 1024 * 1024,
  net_device: { type: "virtio" },
  filesystem: { basefs: { url: path.join(dir, "fs.json") }, baseurl: path.join(dir, "flat") + "/" },
  bzimage_initrd_from_filesystem: true,
  cmdline: "rw root=host9p rootfstype=9p rootflags=trans=virtio,cache=loose console=ttyS0 video=1280x720 init_on_free=on spectre_v2=off pti=off quiet loglevel=3",
  autostart: true,
  screen_dummy: true,
  disable_speaker: true,
});

const t0 = Date.now(), secs = () => ((Date.now() - t0) / 1000).toFixed(0) + "s";
let out = "", stage = 0;
const vram = () => { const m = emu.v86.cpu.devices.vga.svga_memory; let n = 0; for (let i = 0; i < m.length; i += 97) if (m[i]) n++; return n; };
emu.add_listener("serial0-output-byte", b => {
  const c = String.fromCharCode(b);
  process.stdout.write(c);
  out = (out + c).slice(-4000);
  if (stage < 1 && /Kernel panic|end trace 0000/.test(out)) { console.error(`\n== kernel crashed at ${secs()}, giving up on this boot`); process.exit(3); }
  if (stage === 0 && out.includes("GUI_READY")) {
    stage = 0.5;
    console.error(`\n== X is up after ${secs()}; waiting for XFCE to paint the screen`);
    // GUI_READY only means X started. Wait until video memory really holds a drawn desktop.
    let good = 0;
    const iv = setInterval(() => {
      const n = vram();
      if (n > 20000) good++; else good = 0;
      if (good >= 3) {
        clearInterval(iv); stage = 1;
        console.error(`== desktop painted after ${secs()} (vram samples ${n}), settling`);
        setTimeout(() => emu.serial0_send("pgrep -a xfwm4; pgrep -a xfce4-panel; pgrep -a xfdesktop; DISPLAY=:0 xrandr | head -2; free -m; sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; echo LDB_READY_$((6*7))\n"), 20000);
      }
    }, 5000);
  }
  if (stage === 1 && out.includes("LDB_READY_42")) {
    stage = 2;
    setTimeout(async () => {
      const st = new Uint8Array(await emu.save_state());
      const raw = path.join(dir, "state.bin");
      fs.writeFileSync(raw, st);
      execFileSync("zstd", ["-15", "--long=27", "-f", "-q", "--rm", raw, "-o", raw + ".zst"], { stdio: "inherit" });
      console.error(`== snapshot ${(st.length / 1e6).toFixed(0)} MB raw, ${(fs.statSync(raw + ".zst").size / 1e6).toFixed(1)} MB compressed, at ${secs()}`);
      process.exit(0);
    }, 3000);
  }
});
setTimeout(() => {
  console.error("\n== timed out waiting for the desktop; diagnostics follow");
  emu.serial0_send("for f in ~/.local/share/xorg/Xorg.0.log.old ~/.local/share/xorg/Xorg.0.log; do echo \"--- $f\"; grep -E '\\(EE\\)|\\(WW\\)|Fatal|fbdev|FBDEV|Using|Loading' $f | head -60; done; echo '--- xorg.log'; tail -30 /tmp/xorg.log; echo '--- journal'; journalctl -b --no-pager -p warning | tail -40; ls -la /dev/fb0 /dev/dri/card0; id\n");
  setTimeout(() => process.exit(1), 60000);
}, 25 * 60 * 1000);
