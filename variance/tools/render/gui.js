// Lays out a captured Roblox GUI tree like the engine and draws it as HTML
// over the 3D view: UDim2 sizes and positions with AnchorPoint, UIPadding,
// UIListLayout, UIGridLayout, AutomaticSize, UISizeConstraint,
// UIAspectRatioConstraint, UITextSizeConstraint, UIScale, UICorner, UIStroke
// (border or text), TextScaled / TextWrapped, rich text, ZIndex, clipping and
// Roblox defaults for properties the game never set (a Frame's 1px border).

const GUI_INSET = 58;
const FONTS = {
  Michroma: ["Michroma", 400],
  RobotoMono: ["Roboto Mono", 400],
  Code: ["Roboto Mono", 400],
  GothamMedium: ["Montserrat", 500],
  GothamBold: ["Montserrat", 700],
  GothamBlack: ["Montserrat", 900],
  GothamSemibold: ["Montserrat", 600],
  Gotham: ["Montserrat", 400],
  SourceSans: ["Source Sans 3", 400],
  SourceSansBold: ["Source Sans 3", 700],
  SourceSansSemibold: ["Source Sans 3", 600],
  SpecialElite: ["Special Elite", 400],
  Fondamento: ["serif", 400],
  Legacy: ["Source Sans 3", 400],
};
const WEIGHTS = { Thin: 100, ExtraLight: 200, Light: 300, Regular: 400, Medium: 500, SemiBold: 600, Bold: 700, ExtraBold: 800, Heavy: 900 };

const canvas = document.createElement("canvas");
const ctx2d = canvas.getContext("2d");

function udim2(v, pw, ph) {
  if (!v) return [0, 0];
  return [v[1] * pw + v[2], v[3] * ph + v[4]];
}
function udim(v, rel) {
  if (!v) return 0;
  return v[1] * rel + v[2];
}
function rgba(c, t = 0) {
  if (!c) return "transparent";
  return `rgba(${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${Math.round(c[3] * 255)},${(1 - t).toFixed(3)})`;
}
function isGuiObject(k) {
  return ["Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "ViewportFrame", "CanvasGroup", "VideoFrame"].includes(k);
}
function isText(k) {
  return k === "TextLabel" || k === "TextButton" || k === "TextBox";
}
function childOf(node, kind) {
  return node.Ch.find((c) => c.K === kind);
}
function fontOf(P) {
  let [family, weight] = FONTS[P.Font] || ["Source Sans 3", 400];
  if (P.Weight && WEIGHTS[P.Weight]) weight = WEIGHTS[P.Weight];
  if (P.Family) {
    const m = /families\/(\w+)/.exec(P.Family);
    if (m) {
      const key = m[1].replace(/SSm$/, "");
      if (FONTS[key]) family = FONTS[key][0];
      else if (/Gotham/.test(key)) family = "Montserrat";
      else if (/Roboto/.test(key)) family = "Roboto Mono";
    }
  }
  return [family, weight];
}

function plainText(P) {
  let t = P.Text ?? "";
  if (P.RichText) t = t.replace(/<br\s*\/?>/g, "\n").replace(/<[^>]+>/g, "");
  return t.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&").replace(/&quot;/g, '"');
}

function richToHtml(text) {
  const esc = (s) => s.replace(/&(?!(lt|gt|amp|quot|apos);)/g, "&amp;");
  let html = esc(text)
    .replace(/<br\s*\/?>/g, "<br>")
    .replace(/<font([^>]*)>/g, (_, attrs) => {
      let style = "";
      const color = /color\s*=\s*["']?(#[0-9a-fA-F]{6}|rgb\([^)]*\))/.exec(attrs);
      if (color) style += `color:${color[1]};`;
      const size = /size\s*=\s*["']?(\d+)/.exec(attrs);
      if (size) style += `font-size:${size[1]}px;`;
      const tr = /transparency\s*=\s*["']?([\d.]+)/.exec(attrs);
      if (tr) style += `opacity:${1 - Number(tr[1])};`;
      return `<span style="${style}">`;
    })
    .replace(/<\/font>/g, "</span>")
    .replace(/<(uppercase|uc)>/g, '<span style="text-transform:uppercase">')
    .replace(/<\/(uppercase|uc)>/g, "</span>")
    .replace(/<(smallcaps|sc)>/g, '<span style="font-variant:small-caps">')
    .replace(/<\/(smallcaps|sc)>/g, "</span>")
    .replace(/<stroke[^>]*>/g, "<span>")
    .replace(/<\/stroke>/g, "</span>")
    .replace(/<mark[^>]*>/g, "<span>")
    .replace(/<\/mark>/g, "</span>");
  return html;
}

// Pixel bounds of a text block (Roblox line height = TextSize).
function measureText(text, family, weight, size, wrapWidth) {
  ctx2d.font = `${weight} ${size}px "${family}"`;
  const lines = [];
  for (const para of text.split("\n")) {
    if (wrapWidth == null) {
      lines.push(para);
      continue;
    }
    const words = para.split(/(\s+)/);
    let line = "";
    for (const w of words) {
      const next = line + w;
      if (line !== "" && ctx2d.measureText(next.trimEnd()).width > wrapWidth + 0.5) {
        lines.push(line.trimEnd());
        line = w.trimStart();
      } else line = next;
    }
    lines.push(line);
  }
  let width = 0;
  for (const l of lines) width = Math.max(width, ctx2d.measureText(l).width);
  return { w: width, h: lines.length * size, lines: lines.length };
}

function textSizeFor(node, w, h) {
  const P = node.P;
  const [family, weight] = fontOf(P);
  const text = plainText(P);
  const tsc = childOf(node, "UITextSizeConstraint");
  if (P.TextScaled) {
    const max = Math.min(100, tsc?.P.MaxTextSize ?? 100);
    const min = tsc?.P.MinTextSize ?? 1;
    let lo = min, hi = max, best = min;
    while (lo <= hi) {
      const mid = Math.floor((lo + hi) / 2);
      const m = measureText(text, family, weight, mid, w);
      if (m.w <= w + 0.5 && m.h <= h + 0.5) {
        best = mid;
        lo = mid + 1;
      } else hi = mid - 1;
    }
    return best;
  }
  let size = P.TextSize ?? 8;
  if (tsc?.P.MaxTextSize) size = Math.min(size, tsc.P.MaxTextSize);
  return size;
}

const issues = [];

// Measures a node given its parent's content size; returns {w,h} and lays out
// its children (stored on node._kids as {node, x, y}).
function measure(node, pw, ph, forced, fixed) {
  const P = node.P;
  let [w, h] = fixed ? fixed : forced ? forced : udim2(P.Size, pw, ph);
  const scale = childOf(node, "UIScale")?.P.Scale ?? 1;
  const asp = childOf(node, "UIAspectRatioConstraint");
  if (asp) {
    const r = asp.P.AspectRatio ?? 1;
    const dom = asp.P.DominantAxis ?? "Width";
    if (dom === "Height") w = h * r;
    else h = w / r;
  }
  const sc = childOf(node, "UISizeConstraint");
  if (sc) {
    const max = sc.P.MaxSize ? [sc.P.MaxSize[1], sc.P.MaxSize[2]] : [Infinity, Infinity];
    const min = sc.P.MinSize ? [sc.P.MinSize[1], sc.P.MinSize[2]] : [0, 0];
    w = Math.min(Math.max(w, min[0]), max[0]);
    h = Math.min(Math.max(h, min[1]), max[1]);
  }
  const pad = childOf(node, "UIPadding");
  const padL = pad ? udim(pad.P.PaddingLeft, w) : 0;
  const padR = pad ? udim(pad.P.PaddingRight, w) : 0;
  const padT = pad ? udim(pad.P.PaddingTop, h) : 0;
  const padB = pad ? udim(pad.P.PaddingBottom, h) : 0;
  const cw = Math.max(0, w - padL - padR);
  const ch = Math.max(0, h - padT - padB);

  const kids = node.Ch.filter((c) => isGuiObject(c.K) && c.P.Visible !== false);
  const list = childOf(node, "UIListLayout");
  const grid = childOf(node, "UIGridLayout");
  const placed = [];
  const order = (arr, sortOrder) =>
    arr.slice().sort((a, b) => {
      if (sortOrder === "Name") return a.N < b.N ? -1 : a.N > b.N ? 1 : 0;
      return (a.P.LayoutOrder ?? 0) - (b.P.LayoutOrder ?? 0);
    });
  if (grid) {
    const cell = udim2(grid.P.CellSize ?? ["U2", 0, 100, 0, 100], cw, ch);
    const gap = udim2(grid.P.CellPadding ?? ["U2", 0, 5, 0, 5], cw, ch);
    const horizontal = (grid.P.FillDirection ?? "Horizontal") === "Horizontal";
    const maxCells = grid.P.FillDirectionMaxCells || 0;
    let perLine = horizontal ? Math.max(1, Math.floor((cw + gap[0]) / (cell[0] + gap[0]))) : Math.max(1, Math.floor((ch + gap[1]) / (cell[1] + gap[1])));
    if (maxCells > 0) perLine = Math.min(perLine, maxCells);
    const sorted = order(kids, grid.P.SortOrder);
    const lineCount = Math.ceil(sorted.length / perLine);
    const usedW = horizontal ? Math.min(sorted.length, perLine) * (cell[0] + gap[0]) - gap[0] : lineCount * (cell[0] + gap[0]) - gap[0];
    let offX = 0;
    const ha = grid.P.HorizontalAlignment ?? "Left";
    if (ha === "Center") offX = (cw - usedW) / 2;
    else if (ha === "Right") offX = cw - usedW;
    sorted.forEach((k, i) => {
      const a = i % perLine, b = Math.floor(i / perLine);
      const x = horizontal ? a * (cell[0] + gap[0]) : b * (cell[0] + gap[0]);
      const y = horizontal ? b * (cell[1] + gap[1]) : a * (cell[1] + gap[1]);
      const m = measure(k, cw, ch, cell);
      placed.push({ node: k, x: padL + offX + x, y: padT + y, w: m.w, h: m.h });
    });
  } else if (list) {
    const vertical = (list.P.FillDirection ?? "Vertical") === "Vertical";
    const gap = udim(list.P.Padding, vertical ? ch : cw);
    const sorted = order(kids, list.P.SortOrder);
    const sizes = sorted.map((k) => measure(k, cw, ch));
    const total = sizes.reduce((s, m) => s + (vertical ? m.h : m.w), 0) + gap * Math.max(0, sorted.length - 1);
    const mainAlign = vertical ? list.P.VerticalAlignment ?? "Top" : list.P.HorizontalAlignment ?? "Left";
    const crossAlign = vertical ? list.P.HorizontalAlignment ?? "Left" : list.P.VerticalAlignment ?? "Top";
    let cursor = 0;
    const space = vertical ? ch : cw;
    if (mainAlign === "Center") cursor = (space - total) / 2;
    else if (mainAlign === "Bottom" || mainAlign === "Right") cursor = space - total;
    sorted.forEach((k, i) => {
      const m = sizes[i];
      let cross = 0;
      const crossSpace = vertical ? cw : ch;
      const crossSize = vertical ? m.w : m.h;
      if (crossAlign === "Center") cross = (crossSpace - crossSize) / 2;
      else if (crossAlign === "Right" || crossAlign === "Bottom") cross = crossSpace - crossSize;
      const x = vertical ? cross : cursor;
      const y = vertical ? cursor : cross;
      placed.push({ node: k, x: padL + x, y: padT + y, w: m.w, h: m.h });
      cursor += (vertical ? m.h : m.w) + gap;
    });
  } else {
    for (const k of kids) {
      const m = measure(k, cw, ch);
      const [px, py] = udim2(k.P.Position, cw, ch);
      const ap = k.P.AnchorPoint ?? ["V2", 0, 0];
      placed.push({ node: k, x: padL + px - ap[1] * m.w, y: padT + py - ap[2] * m.h, w: m.w, h: m.h });
    }
  }

  // AutomaticSize: grow to the children and the text.
  const auto = P.AutomaticSize ?? "None";
  if (auto !== "None") {
    let ew = 0, eh = 0;
    for (const p of placed) {
      ew = Math.max(ew, p.x + p.w);
      eh = Math.max(eh, p.y + p.h);
    }
    ew += padR;
    eh += padB;
    if (isText(node.K) && (P.Text ?? "") !== "") {
      const [family, weight] = fontOf(P);
      const size = P.TextSize ?? 8;
      const wrapW = P.TextWrapped && auto === "Y" ? cw : null;
      const m = measureText(plainText(P), family, weight, size, wrapW);
      ew = Math.max(ew, m.w + padL + padR);
      eh = Math.max(eh, m.h + padT + padB);
    }
    const nw = auto === "X" || auto === "XY" ? Math.max(w, ew) : w;
    const nh = auto === "Y" || auto === "XY" ? Math.max(h, eh) : h;
    if (!fixed && (Math.abs(nw - w) > 0.5 || Math.abs(nh - h) > 0.5)) {
      // The engine resolves AutomaticSize before aligning children: lay out
      // again inside the final size.
      return measure(node, pw, ph, forced, [nw, nh]);
    }
    w = nw;
    h = nh;
  }
  node._kids = placed;
  node._w = w;
  node._h = h;
  node._pad = [padL, padT, padR, padB];
  node._scale = scale;
  return { w, h };
}

function draw(node, el, x, y, w, h, path) {
  const P = node.P;
  const div = document.createElement("div");
  const s = div.style;
  s.position = "absolute";
  s.left = `${x}px`;
  s.top = `${y}px`;
  s.width = `${w}px`;
  s.height = `${h}px`;
  s.zIndex = String(P.ZIndex ?? 1);
  s.boxSizing = "border-box";
  const bt = P.BackgroundTransparency ?? 0;
  const drawsBackground = !["TextLabel", "ImageLabel"].includes(node.K) || bt < 1 || P.BackgroundTransparency !== undefined;
  if (bt < 1 && drawsBackground) {
    s.background = rgba(P.BackgroundColor3 ?? ["C3", 0.64, 0.64, 0.64], bt);
  }
  // Roblox's default Frame border (1px, dark) when nobody zeroed it.
  const border = P.BorderSizePixel ?? 1;
  if (border > 0 && bt < 1) {
    s.boxShadow = `0 0 0 ${border}px rgba(27,42,53,${1 - bt})`;
    issues.push(`default border: ${path}`);
  }
  const gradient = childOf(node, "UIGradient");
  if (gradient && gradient.P.Keys && bt < 1 && gradient.P.Enabled !== false) {
    // UIGradient multiplies the background colour.
    const base = P.BackgroundColor3 ?? ["C3", 0.64, 0.64, 0.64];
    const stops = gradient.P.Keys.map((k) => {
      const c = ["C3", k[1] * base[1], k[2] * base[2], k[3] * base[3]];
      return `${rgba(c, bt)} ${(k[0] * 100).toFixed(1)}%`;
    });
    const angle = 90 + (gradient.P.Rotation ?? 0);
    s.background = `linear-gradient(${angle}deg, ${stops.join(", ")})`;
  }
  const corner = childOf(node, "UICorner");
  if (corner) {
    const r = corner.P.CornerRadius ?? ["U", 0, 8];
    s.borderRadius = `${udim(r, Math.min(w, h))}px`;
  }
  const stroke = childOf(node, "UIStroke");
  const strokeMode = stroke ? stroke.P.ApplyStrokeMode ?? "Contextual" : null;
  if (stroke && (strokeMode === "Border" || !isText(node.K))) {
    const t = stroke.P.Thickness ?? 1;
    const c = rgba(stroke.P.Color ?? ["C3", 0, 0, 0], stroke.P.Transparency ?? 0);
    s.boxShadow = `0 0 0 ${t}px ${c}`;
  }
  if (P.ClipsDescendants || node.K === "ScrollingFrame") s.overflow = "hidden";
  if (P.Rotation) s.transform = `rotate(${P.Rotation}deg)`;
  if (node._scale !== 1) {
    const ap = P.AnchorPoint ?? ["V2", 0, 0];
    s.transform = (s.transform || "") + ` scale(${node._scale})`;
    s.transformOrigin = `${ap[1] * 100}% ${ap[2] * 100}%`;
  }
  if (node.K === "ImageLabel" || node.K === "ImageButton") {
    if (P.Image && P.Image !== "") {
      const img = document.createElement("div");
      img.style.cssText = `position:absolute;inset:0;border-radius:inherit;background:${rgba(P.ImageColor3 ?? ["C3", 1, 1, 1], Math.max(P.ImageTransparency ?? 0, 0.55))};outline:1px dashed rgba(255,255,255,0.25)`;
      div.appendChild(img);
    }
  }
  if (isText(node.K)) {
    const text = P.Text ?? "";
    if (text !== "") {
      const [pl, pt, pr, pb] = node._pad;
      const tw = w - pl - pr;
      const th = h - pt - pb;
      const size = textSizeFor(node, tw, th);
      const [family, weight] = fontOf(P);
      const t = document.createElement("div");
      const ts = t.style;
      ts.position = "absolute";
      ts.left = `${pl}px`;
      ts.top = `${pt}px`;
      ts.width = `${tw}px`;
      ts.height = `${th}px`;
      ts.display = "flex";
      ts.flexDirection = "column";
      const xa = P.TextXAlignment ?? "Center";
      const ya = P.TextYAlignment ?? "Center";
      ts.justifyContent = ya === "Top" ? "flex-start" : ya === "Bottom" ? "flex-end" : "center";
      ts.textAlign = xa === "Left" ? "left" : xa === "Right" ? "right" : "center";
      ts.fontFamily = `"${family}"`;
      ts.fontWeight = String(weight);
      ts.fontSize = `${size}px`;
      ts.lineHeight = `${size}px`;
      ts.color = rgba(P.TextColor3 ?? ["C3", 0.1, 0.1, 0.1], P.TextTransparency ?? 0);
      ts.whiteSpace = P.TextWrapped ? "pre-wrap" : "pre";
      ts.overflow = "visible";
      ts.zIndex = "0";
      if (stroke && strokeMode === "Contextual") {
        const c = rgba(stroke.P.Color ?? ["C3", 0, 0, 0], stroke.P.Transparency ?? 0);
        ts.webkitTextStroke = `${(stroke.P.Thickness ?? 1) * 2}px ${c}`;
        ts.paintOrder = "stroke fill";
      }
      const inner = document.createElement("span");
      inner.style.display = "block";
      if (P.RichText) inner.innerHTML = richToHtml(text);
      else inner.textContent = text;
      t.appendChild(inner);
      div.appendChild(t);
      if (!P.TextScaled && !P.TextWrapped && (P.AutomaticSize ?? "None") === "None") {
        const m = measureText(plainText(P), family, weight, size, null);
        if (m.w > tw + 2) issues.push(`text overflows (${Math.round(m.w)}>${Math.round(tw)}px): ${path} "${plainText(P).slice(0, 40)}"`);
      }
    }
  }
  el.appendChild(div);
  const kids = (node._kids || []).slice().sort((a, b) => (a.node.P.ZIndex ?? 1) - (b.node.P.ZIndex ?? 1));
  for (const k of kids) draw(k.node, div, k.x, k.y, k.w, k.h, `${path}/${k.node.N}`);
}

window.renderGui = function renderGui(gui) {
  const root = document.getElementById("gui");
  root.innerHTML = "";
  issues.length = 0;
  if (!gui) return [];
  const [VW, VH] = gui.Viewport;
  const roots = gui.Roots.filter((r) => r.P.Enabled !== false).sort((a, b) => (a.P.DisplayOrder ?? 0) - (b.P.DisplayOrder ?? 0));
  roots.forEach((sg, i) => {
    const inset = sg.P.IgnoreGuiInset ? 0 : GUI_INSET;
    const scale = childOf(sg, "UIScale")?.P.Scale ?? 1;
    const layer = document.createElement("div");
    layer.style.cssText = `position:absolute;left:0;top:${inset}px;width:${VW / scale}px;height:${(VH - inset) / scale}px;transform:scale(${scale});transform-origin:0 0;z-index:${i + 1}`;
    const vw = VW / scale, vh = (VH - inset) / scale;
    const kids = sg.Ch.filter((c) => isGuiObject(c.K) && c.P.Visible !== false);
    for (const k of kids) {
      const m = measure(k, vw, vh);
      const [px, py] = udim2(k.P.Position, vw, vh);
      const ap = k.P.AnchorPoint ?? ["V2", 0, 0];
      draw(k, layer, px - ap[1] * m.w, py - ap[2] * m.h, m.w, m.h, `${sg.N}/${k.N}`);
    }
    root.appendChild(layer);
  });
  window.guiIssues = [...new Set(issues)];
  return window.guiIssues;
};
window.guiReady = true;
