// Builds a three.js scene from a tests/snapshot.luau frame and renders it
// from the client's camera. Roblox and three.js share conventions (right
// handed, Y up, cameras look down -Z, vertical field of view), so CFrames map
// straight onto matrices.
import * as THREE from "three";

let W = 1280;
let H = 720;

const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setSize(W, H);
renderer.setPixelRatio(1);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.NoToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.getElementById("view").appendChild(renderer.domElement);

function matrixOf(cf) {
  const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = cf;
  const m = new THREE.Matrix4();
  m.set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
  return m;
}

function colorOf(c) {
  return new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);
}

const ROUGH = {
  SmoothPlastic: 0.45, Plastic: 0.6, Metal: 0.35, DiamondPlate: 0.4, CorrodedMetal: 0.8,
  Glass: 0.05, Wood: 0.8, WoodPlanks: 0.8, Concrete: 0.95, Slate: 0.9, Marble: 0.3,
  Granite: 0.8, Brick: 0.95, Fabric: 1, Carpet: 1, Leather: 0.7, Foil: 0.2, Ice: 0.1,
  Cobblestone: 0.95, Pebble: 0.95, Asphalt: 1, Rubber: 0.9, Cardboard: 1,
};
const METAL = { Metal: 0.8, DiamondPlate: 0.7, CorrodedMetal: 0.5, Foil: 0.9 };

const wedgeGeometry = (() => {
  // Roblox wedge: the slope faces front (-Z); the tall face is at the back.
  const g = new THREE.BufferGeometry();
  const v = [
    [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5],
    [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5],
  ];
  const tris = [
    [0, 2, 1], [0, 3, 2], // bottom
    [3, 5, 2], [3, 4, 5], // back
    [0, 1, 5], [0, 5, 4], // slope
    [0, 4, 3], // left
    [1, 2, 5], // right
  ];
  const pos = [];
  for (const t of tris) for (const i of t) pos.push(...v[i]);
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
})();

const box = new THREE.BoxGeometry(1, 1, 1);
const ball = new THREE.SphereGeometry(0.5, 24, 16);
const cyl = new THREE.CylinderGeometry(0.5, 0.5, 1, 28);
cyl.rotateZ(Math.PI / 2); // Roblox cylinders run along X
const headGeo = new THREE.CylinderGeometry(0.5, 0.5, 1, 28); // SpecialMesh "Head"

function materialFor(p) {
  const color = colorOf(p.C);
  const opacity = 1 - p.T;
  const transparent = p.T > 0.01;
  if (p.M === "Neon") {
    return new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(1.6), transparent, opacity });
  }
  if (p.M === "ForceField") {
    return new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.25 * opacity, depthWrite: false });
  }
  if (p.M === "Glass") {
    return new THREE.MeshStandardMaterial({ color, roughness: 0.05, metalness: 0.1, transparent: true, opacity: Math.min(opacity, 0.45) });
  }
  return new THREE.MeshStandardMaterial({
    color,
    roughness: ROUGH[p.M] ?? 0.7,
    metalness: Math.max(METAL[p.M] ?? 0, p.R || 0),
    transparent,
    opacity,
    depthWrite: !transparent || opacity > 0.6,
  });
}

function meshFor(p) {
  let geo = box;
  let scale = new THREE.Vector3(p.S[0], p.S[1], p.S[2]);
  if (p.K === "Ball") {
    geo = ball;
    const d = Math.min(p.S[0], p.S[1], p.S[2]);
    scale.set(d, d, d);
  } else if (p.K === "Cylinder") {
    geo = cyl;
    const d = Math.min(p.S[1], p.S[2]);
    scale.set(p.S[0], d, d);
  } else if (p.K === "WedgePart") {
    geo = wedgeGeometry;
  }
  if (p.Mesh) {
    const s = p.Mesh.Scale || [1, 1, 1];
    if (p.Mesh.Type === "Sphere") {
      geo = ball;
      scale.set(p.S[0] * s[0], p.S[1] * s[1], p.S[2] * s[2]);
    } else if (p.Mesh.Type === "Head") {
      geo = headGeo;
      scale.set(p.S[0] * s[0] * 0.6, p.S[1] * s[1], p.S[2] * s[2]);
    } else if (p.Mesh.Type === "Cylinder") {
      geo = cyl;
    }
  }
  const mesh = new THREE.Mesh(geo, materialFor(p));
  mesh.matrixAutoUpdate = false;
  mesh.matrix.copy(matrixOf(p.CF)).multiply(new THREE.Matrix4().makeScale(scale.x, scale.y, scale.z));
  mesh.castShadow = p.T < 0.5 && p.M !== "Neon";
  mesh.receiveShadow = true;
  return mesh;
}

const FACE = {
  Front: [0, 0, -1], Back: [0, 0, 1], Top: [0, 1, 0], Bottom: [0, -1, 0], Right: [1, 0, 0], Left: [-1, 0, 0],
};

window.renderFrame = function renderFrame(frame, options = {}) {
  const S = frame.Scene;
  if (frame.Gui && frame.Gui.Viewport) {
    [W, H] = frame.Gui.Viewport;
  }
  renderer.setSize(W, H);
  for (const id of ["view", "gui", "tint"]) {
    const el = document.getElementById(id);
    el.style.width = `${W}px`;
    el.style.height = `${H}px`;
  }
  const scene = new THREE.Scene();
  const L = S.Lighting;
  scene.background = colorOf(L.FogColor).multiplyScalar(0.35);

  for (const p of S.Parts) scene.add(meshFor(p));

  // Ambient + a sun from the clock time (rooms are enclosed; walls shadow it).
  const amb = colorOf(L.Ambient);
  scene.add(new THREE.AmbientLight(amb, 1.4));
  if (options.bright) {
    scene.add(new THREE.AmbientLight(0xffffff, 1.2));
    const key = new THREE.DirectionalLight(0xffffff, 1.5);
    key.position.set(0.4, 1, 0.6).multiplyScalar(100).add(new THREE.Vector3().setFromMatrixPosition(matrixOf(S.Camera.CF)));
    scene.add(key);
  }
  scene.add(new THREE.HemisphereLight(colorOf(L.OutdoorAmbient), amb, 0.35));
  const t = ((L.ClockTime ?? 14) - 6) / 12 * Math.PI;
  if (Math.sin(t) > 0.02) {
    const sun = new THREE.DirectionalLight(0xfff3e0, (L.Brightness ?? 1) * 1.2);
    sun.position.set(Math.cos(t) * 300, Math.sin(t) * 300, 120);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    const sc = sun.shadow.camera;
    sc.left = -150; sc.right = 150; sc.top = 150; sc.bottom = -150; sc.far = 800;
    scene.add(sun);
  }

  // Local lights nearest the camera (forward renderer; keep shader size sane).
  const camM = matrixOf(S.Camera.CF);
  const camPos = new THREE.Vector3().setFromMatrixPosition(camM);
  const lights = S.Lights.map((l) => ({ l, d: new THREE.Vector3(l.CF[0], l.CF[1], l.CF[2]).distanceTo(camPos) }))
    .filter((x) => x.d < x.l.Range + 90)
    .sort((a, b) => a.d - b.d)
    .slice(0, options.maxLights ?? 20);
  let shadowed = 0;
  for (const { l } of lights) {
    const m = matrixOf(l.CF);
    const pos = new THREE.Vector3().setFromMatrixPosition(m);
    const color = colorOf(l.C);
    // Roblox lights reach their Brightness around a quarter of their Range
    // and fade to nothing at Range.
    const intensity = (l.B * l.Range * l.Range) / 14;
    if (l.K === "PointLight") {
      const pl = new THREE.PointLight(color, intensity, l.Range, 2);
      pl.position.copy(pos);
      scene.add(pl);
    } else {
      const f = FACE[l.Face] || FACE.Front;
      const dir = new THREE.Vector3(...f).transformDirection(m);
      const angle = l.K === "SurfaceLight" ? Math.min(l.Angle, 170) : l.Angle;
      const sl = new THREE.SpotLight(color, intensity * 1.2, l.Range, THREE.MathUtils.degToRad(Math.min(angle, 170) / 2), 0.4, 2);
      sl.position.copy(pos);
      sl.target.position.copy(pos.clone().add(dir));
      if (shadowed < 3) {
        sl.castShadow = true;
        sl.shadow.mapSize.set(1024, 1024);
        shadowed++;
      }
      scene.add(sl);
      scene.add(sl.target);
    }
  }

  for (const e of options.bright ? [] : L.Effects) {
    if (e.K === "Atmosphere" && e.Density > 0) {
      scene.fog = new THREE.FogExp2(colorOf(e.Color), e.Density * 0.02);
    }
  }
  if (!scene.fog && !options.bright && L.FogEnd < 5000) scene.fog = new THREE.Fog(colorOf(L.FogColor), L.FogStart, L.FogEnd);

  const camera = new THREE.PerspectiveCamera(S.Camera.Fov, W / H, 0.1, 3000);
  camera.matrixAutoUpdate = false;
  camera.matrix.copy(camM);
  camera.matrixWorld.copy(camM);
  camera.matrixWorldInverse.copy(camM).invert();
  const override = options.camera;
  if (override) {
    camera.matrixAutoUpdate = true;
    camera.position.set(...override.pos);
    camera.lookAt(new THREE.Vector3(...override.at));
    camera.fov = override.fov ?? 50;
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld();
  }

  // Post: colour correction and blur as CSS filters on the canvas.
  const filters = [];
  let tint = null;
  for (const e of options.bright ? [] : L.Effects) {
    if (e.K === "CC") {
      filters.push(`brightness(${(1 + e.Brightness).toFixed(3)})`, `contrast(${(1 + e.Contrast).toFixed(3)})`, `saturate(${Math.max(0, 1 + e.Saturation).toFixed(3)})`);
      if (e.Tint && (e.Tint[0] < 0.99 || e.Tint[1] < 0.99 || e.Tint[2] < 0.99)) tint = e.Tint;
    } else if (e.K === "Blur" && e.Size > 0.5) {
      filters.push(`blur(${(e.Size / 5).toFixed(2)}px)`);
    }
  }
  renderer.toneMappingExposure = Math.pow(2, L.Exposure || 0);
  renderer.domElement.style.filter = filters.join(" ");
  const tintEl = document.getElementById("tint");
  tintEl.style.display = tint ? "block" : "none";
  if (tint) tintEl.style.background = `rgb(${tint.map((x) => Math.round(x * 255)).join(",")})`;

  renderer.render(scene, camera);
  scene.traverse((o) => {
    if (o.material && o.material.dispose) o.material.dispose();
  });
  return true;
};
window.sceneReady = true;
