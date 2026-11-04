// Opens the deployed desktop in headless Chromium: checks the screen is drawn, that it reacts,
// and that Save + reload restores the machine. Writes shot-1.png / shot-2.png.
import { chromium } from "playwright";
const URL = process.argv[2] || "http://localhost:8000/";
const t0 = Date.now(), secs = () => ((Date.now() - t0) / 1000).toFixed(1) + "s";
const b = await chromium.launch();
const page = await b.newPage({ viewport: { width: 1280, height: 720 } });
page.on("pageerror", e => console.log("PAGE ERROR", e.message));
page.on("console", m => { if (m.type() === "error") console.log("CONSOLE", m.text()); });
const stats = () => page.evaluate(() => {
  const c = __os.canvas, x = c.getContext("2d"), d = x.getImageData(0, 0, c.width, c.height).data;
  let lit = 0, colors = new Set(), sum = 0;
  for (let i = 0; i < d.length; i += 16) { const v = d[i] + d[i + 1] + d[i + 2]; if (v > 30) lit++; colors.add((d[i] >> 4) << 8 | (d[i + 1] >> 4) << 4 | d[i + 2] >> 4); sum = (sum * 31 + v) >>> 0; }
  return { size: c.width + "x" + c.height, lit: (100 * lit / (d.length / 16)).toFixed(1) + "%", colors: colors.size, hash: sum };
});
async function serial(cmd, marker, ms = 60000) {
  await page.evaluate(() => { if (!window.__ser) { window.__ser = ""; __os.emu.add_listener("serial0-output-byte", b => { window.__ser += String.fromCharCode(b); }); } });
  await page.evaluate(c => __os.emu.serial0_send(c + "\n"), cmd);
  await page.waitForFunction(m => window.__ser.includes(m), marker, { timeout: ms });
  return page.evaluate(m => { const s = window.__ser; window.__ser = ""; return s.slice(0, s.indexOf(m)); }, marker);
}
async function boot(label) {
  await page.goto(URL);
  await page.waitForFunction(() => window.__os && __os.booted && __os.ready, null, { timeout: 300000 });
  await page.waitForTimeout(25000);
  console.log(`== ${label}: up at ${secs()}, status "${await page.textContent("#stat")}", screen`, JSON.stringify(await stats()));
}
try {
  await boot("first visit");
  await page.screenshot({ path: "shot-1.png" });
  console.log(await serial("pgrep -c Xorg; pgrep -c xfwm4; echo HELLO > ~/kept.txt; echo T1_$((40+2))", "T1_42"));
  const before = await stats();
  await serial("DISPLAY=:0 xfce4-terminal --geometry=90x24+120+90 >/dev/null 2>&1 & echo T2_$((40+2))", "T2_42");
  await page.waitForTimeout(25000);
  const after = await stats();
  console.log("== terminal window opened:", before.hash !== after.hash ? "screen changed" : "NO CHANGE", JSON.stringify(after));
  await page.screenshot({ path: "shot-2.png" });
  await page.evaluate(() => __os.save());
  await page.waitForFunction(() => /saved/.test(document.querySelector("#stat").textContent), null, { timeout: 300000 });
  console.log(`== saved at ${secs()}: ${await page.textContent("#toast")}`);
  await boot("reload");
  const o = await serial("cat ~/kept.txt; echo T3_$((40+2))", "T3_42");
  console.log(o.includes("HELLO") ? "== RESTORE OK" : "== RESTORE FAILED " + o);
} catch (e) {
  console.log("== TEST FAILED at " + secs() + ": " + e.message);
  try { await page.screenshot({ path: "shot-fail.png" }); } catch (_) {}
}
await b.close();
