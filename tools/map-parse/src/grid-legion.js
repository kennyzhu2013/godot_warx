import fs from "node:fs";

const root = "d:/game2/rpg/mpqediten64/Work/godot_war3/assets/map-parsed/legiontd";
const regions = JSON.parse(fs.readFileSync(`${root}/regions.json`, "utf8"));
const doodads = JSON.parse(fs.readFileSync(`${root}/doodads.json`, "utf8"));
const pathing = JSON.parse(fs.readFileSync(`${root}/pathing.json`, "utf8"));
const info = JSON.parse(fs.readFileSync(`${root}/info.json`, "utf8"));
const bytes = Buffer.from(pathing.cellsBase64, "base64");
const W = pathing.width;
const ox = pathing.origin.x;
const oy = pathing.origin.y;

function flag(x, y) {
  const i = Math.floor((x - ox) / 32);
  const j = Math.floor((y - oy) / 32);
  if (i < 0 || j < 0 || i >= W || j >= pathing.height) return -1;
  return bytes[j * W + i];
}

const rects = regions.regions.filter((r) => r.name.startsWith("RctPlayer"));
for (const rg of rects) {
  const b = rg.bounds;
  let walk = 0;
  let build = 0;
  let total = 0;
  let blocked = 0;
  for (let y = b.bottom + 64; y < b.top; y += 128) {
    for (let x = b.left + 64; x < b.right; x += 128) {
      const f = flag(x, y);
      total += 1;
      if (f < 0) continue;
      if ((f & 2) === 0) walk += 1;
      if ((f & 8) === 0) build += 1;
      if ((f & 2) !== 0) blocked += 1;
    }
  }
  console.log(rg.name, `samples ${total} walk ${walk} build ${build} nowalk ${blocked}`);
}

function cluster(points) {
  const gap = 900;
  const parent = points.map((_, i) => i);
  const find = (i) => {
    while (parent[i] !== i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  };
  for (let i = 0; i < points.length; i += 1) {
    for (let j = i + 1; j < points.length; j += 1) {
      if (Math.abs(points[i].x - points[j].x) < gap && Math.abs(points[i].y - points[j].y) < gap) {
        parent[find(i)] = find(j);
      }
    }
  }
  const groups = new Map();
  points.forEach((p, i) => {
    const r = find(i);
    if (!groups.has(r)) groups.set(r, []);
    groups.get(r).push(p);
  });
  return [...groups.values()];
}

for (const id of ["D00H", "D00J"]) {
  const pts = doodads.doodads.filter((d) => d.id === id).map((d) => d.position);
  console.log("\n==", id);
  for (const g of cluster(pts)) {
    if (g.length < 8) continue;
    const xs = g.map((p) => p.x).sort((a, b) => a - b);
    const ys = g.map((p) => p.y).sort((a, b) => a - b);
    console.log(
      "n", g.length,
      "x", xs.map((v) => Math.round(v)).join(","),
      "y", ys.map((v) => Math.round(v)).join(","),
    );
    const cx = xs.reduce((s, v) => s + v, 0) / g.length;
    const cy = ys.reduce((s, v) => s + v, 0) / g.length;
    let best = "";
    let bestD = 1e12;
    for (const rg of rects) {
      const b = rg.bounds;
      const rx = (b.left + b.right) / 2;
      const ry = (b.bottom + b.top) / 2;
      const d = (rx - cx) ** 2 + (ry - cy) ** 2;
      if (d < bestD) {
        bestD = d;
        best = rg.name;
      }
    }
    console.log("  centroid", Math.round(cx), Math.round(cy), "nearest", best, "dist", Math.round(Math.sqrt(bestD)));
    for (const p of g) {
      const f = flag(p.x, p.y);
      console.log("   ", Math.round(p.x), Math.round(p.y), "f", f, "nowalk", (f & 2) !== 0, "nobuild", (f & 8) !== 0);
    }
  }
}

console.log("\n== starts inside RctPlayer ==");
for (const p of info.players) {
  const hits = rects.filter((rg) => {
    const b = rg.bounds;
    return p.startPosition.x >= b.left && p.startPosition.x <= b.right
      && p.startPosition.y >= b.bottom && p.startPosition.y <= b.top;
  }).map((rg) => rg.name);
  console.log(p.playerNum, p.name, hits.join(",") || "NONE");
}
