// Renders tests/snapshot.luau frames to PNG.
//
//   node tools/render/render.mjs <frames dir or .json files...> [--out dir]
//        [--no-gui] [--camera x,y,z:ax,ay,az[:fov]]
//
// Needs Chromium (PLAYWRIGHT_BROWSERS_PATH or CHROMIUM=path) and `npm install`
// in tools/render. The 3D scene is drawn with three.js; the GUI tree is laid
// out as HTML (gui.js).
import { chromium } from "playwright-core";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
let outDir = null;
let gui = true;
let cameraOverride = null;
let bright = false;
let suffix = "";
let sheet = null;
let cols = 4;
let tileW = 426;
const inputs = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--out") outDir = args[++i];
  else if (a === "--no-gui") gui = false;
  else if (a === "--bright") bright = true;
  else if (a === "--suffix") suffix = args[++i];
  else if (a === "--sheet") sheet = args[++i];
  else if (a === "--cols") cols = Number(args[++i]);
  else if (a === "--tile") tileW = Number(args[++i]);
  else if (a === "--camera") {
    const [pos, at, fov] = args[++i].split(":");
    cameraOverride = { pos: pos.split(",").map(Number), at: at.split(",").map(Number), fov: fov ? Number(fov) : 50 };
  } else inputs.push(a);
}
const files = [];
for (const input of inputs) {
  if (fs.statSync(input).isDirectory()) {
    for (const f of fs.readdirSync(input).sort()) if (f.endsWith(".json")) files.push(path.join(input, f));
  } else files.push(input);
}
if (files.length === 0) {
  console.error("no frames");
  process.exit(1);
}

const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  let file = null;
  if (url === "/" || url === "/index.html") file = path.join(here, "index.html");
  else if (url === "/three.module.js") file = path.join(here, "node_modules/three/build/three.module.js");
  else if (url === "/three.core.js") file = path.join(here, "node_modules/three/build/three.core.js");
  else file = path.join(here, path.normalize(url).replace(/^([/\\])+/, ""));
  if (!file.startsWith(here) || !fs.existsSync(file)) {
    res.writeHead(404);
    res.end();
    return;
  }
  res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const executablePath = process.env.CHROMIUM || "/opt/pw-browsers/chromium";
const browser = await chromium.launch({
  executablePath,
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on("console", (m) => {
  if (m.type() === "error" || m.type() === "warning") console.log("page:", m.text());
});
page.on("pageerror", (e) => console.log("page error:", e.message));
await page.goto(`http://127.0.0.1:${port}/`);
await page.waitForFunction(() => window.sceneReady === true && window.guiReady === true && window.fontsReady === true, null, { timeout: 30000 });

const shots = [];
for (const file of files) {
  const frame = JSON.parse(fs.readFileSync(file, "utf8"));
  const issues = await page.evaluate(
    ([f, g, cam, b]) => {
      window.renderFrame(f, { camera: cam, bright: b });
      return window.renderGui(g ? f.Gui : null);
    },
    [frame, gui, cameraOverride, bright]
  );
  if (issues && issues.length && process.env.GUI_ISSUES) for (const i of issues) console.log("  gui:", i);
  if (sheet) {
    shots.push({ label: frame.Label, data: (await page.screenshot()).toString("base64") });
    continue;
  }
  const dir = outDir || path.dirname(file);
  fs.mkdirSync(dir, { recursive: true });
  const png = path.join(dir, path.basename(file, ".json") + suffix + ".png");
  await page.screenshot({ path: png });
  console.log(png);
}
if (sheet) {
  const tileH = Math.round((tileW * 720) / 1280);
  const rows = Math.ceil(shots.length / cols);
  const sheetPage = await browser.newPage({ viewport: { width: cols * tileW, height: rows * tileH } });
  const cells = shots
    .map(
      (s) =>
        `<div style="position:relative;width:${tileW}px;height:${tileH}px;float:left"><img src="data:image/png;base64,${s.data}" style="width:100%;height:100%"><span style="position:absolute;left:4px;top:2px;font:bold 13px monospace;color:#ff0;text-shadow:0 0 3px #000">${s.label}</span></div>`
    )
    .join("");
  await sheetPage.setContent(`<body style="margin:0;background:#000">${cells}</body>`);
  await sheetPage.screenshot({ path: sheet, fullPage: true });
  console.log(sheet);
}
await browser.close();
server.close();
