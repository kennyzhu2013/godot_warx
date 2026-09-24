import fs from "node:fs";
import { LEGION_PARSED_DIR } from "./legion-paths.js";

const root = LEGION_PARSED_DIR;
const info = JSON.parse(fs.readFileSync(`${root}/info.json`, "utf8"));
const regions = JSON.parse(fs.readFileSync(`${root}/regions.json`, "utf8"));
const doodads = JSON.parse(fs.readFileSync(`${root}/doodads.json`, "utf8"));
const pathing = JSON.parse(fs.readFileSync(`${root}/pathing.json`, "utf8"));
const cells = Buffer.from(pathing.cellsBase64, "base64");

function norm(b, order) {
  const [a, c, d, e] = order === "lbrt"
    ? [b.left, b.bottom, b.right, b.top]
    : [b.left, b.right, b.bottom, b.top];
  // file order left,bottom,right,top stored in parser fields left,right,bottom,top
  const raw = order === "lbrt"
    ? { l: b.left, b: b.right, r: b.bottom, t: b.top }
    : { l: b.left, r: b.right, b: b.bottom, t: b.top };
  void a; void c; void d; void e;
  return {
    x0: Math.min(raw.l, raw.r),
    x1: Math.max(raw.l, raw.r),
    y0: Math.min(raw.b, raw.t),
    y1: Math.max(raw.b, raw.t),
  };
}

function inside(n, x, y) {
  return x >= n.x0 && x <= n.x1 && y >= n.y0 && y <= n.y1;
}

console.log("--- starts vs regions (parser order vs left/bottom/right/top) ---");
for (const p of info.players) {
  const x = p.startPosition.x;
  const y = p.startPosition.y;
  const hitA = [];
  const hitB = [];
  for (const rg of regions.regions) {
    if (inside(norm(rg.bounds, "as"), x, y)) hitA.push(rg.name);
    if (inside(norm(rg.bounds, "lbrt"), x, y)) hitB.push(rg.name);
  }
  console.log(`P${p.playerNum} ${p.name} (${x},${y}) as=[${hitA.join(",")}] lbrt=[${hitB.join(",")}]`);
}

console.log("--- RctPlayer normalized both ways ---");
for (const rg of regions.regions.filter((r) => r.name.startsWith("RctPlayer"))) {
  const a = norm(rg.bounds, "as");
  const b = norm(rg.bounds, "lbrt");
  console.log(
    rg.name,
    `as ${a.x0},${a.y0} ${Math.round(a.x1 - a.x0)}x${Math.round(a.y1 - a.y0)}`,
    `lbrt ${b.x0},${b.y0} ${Math.round(b.x1 - b.x0)}x${Math.round(b.y1 - b.y0)}`,
  );
}

const byId = {};
for (const d of doodads.doodads) {
  if (!byId[d.id]) byId[d.id] = [];
  byId[d.id].push(d.position);
}

function cluster(points, gap) {
  const parent = points.map((_, i) => i);
  const find = (i) => {
    while (parent[i] !== i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  };
  const buckets = new Map();
  const key = (x, y) => `${x},${y}`;
  points.forEach((p, i) => {
    const gx = Math.floor(p.x / gap);
    const gy = Math.floor(p.y / gap);
    for (let dx = -1; dx <= 1; dx += 1) {
      for (let dy = -1; dy <= 1; dy += 1) {
        const list = buckets.get(key(gx + dx, gy + dy));
        if (!list) continue;
        for (const j of list) {
          if (Math.abs(points[j].x - p.x) <= gap && Math.abs(points[j].y - p.y) <= gap) {
            parent[find(i)] = find(j);
          }
        }
      }
    }
    const k = key(gx, gy);
    if (!buckets.has(k)) buckets.set(k, []);
    buckets.get(k).push(i);
  });
  const groups = new Map();
  points.forEach((p, i) => {
    const r = find(i);
    if (!groups.has(r)) groups.set(r, []);
    groups.get(r).push(p);
  });
  return [...groups.values()];
}

console.log("--- doodad clusters gap 400 ---");
for (const id of Object.keys(byId)) {
  const groups = cluster(byId[id], 400);
  const sizes = groups.map((g) => g.length).sort((a, b) => b - a);
  const boxes = groups
    .filter((g) => g.length >= 8)
    .slice(0, 6)
    .map((g) => {
      const xs = g.map((p) => p.x);
      const ys = g.map((p) => p.y);
      const x0 = Math.min(...xs);
      const x1 = Math.max(...xs);
      const y0 = Math.min(...ys);
      const y1 = Math.max(...ys);
      return `${g.length}@(${Math.round(x0)},${Math.round(y0)}) ${Math.round(x1 - x0)}x${Math.round(y1 - y0)}`;
    });
  console.log(id, "n", byId[id].length, "groups", groups.length, "top", sizes.slice(0, 8).join(","), boxes.join(" | "));
}

const ox = pathing.origin.x;
const oy = pathing.origin.y;
const W = pathing.width;
function flagAt(x, y) {
  const i = Math.floor((x - ox) / 32);
  const j = Math.floor((y - oy) / 32);
  if (i < 0 || j < 0 || i >= W || j >= pathing.height) return -1;
  return cells[j * W + i];
}
console.log("--- path flag at starts (bit2 = nowalk) ---");
for (const p of info.players) {
  const f = flagAt(p.startPosition.x, p.startPosition.y);
  console.log(`P${p.playerNum}`, f, "nowalk", (f & 2) !== 0, "nobuild", (f & 8) !== 0);
}

console.log("--- KOdr points ---");
for (const p of byId.KOdr ?? []) console.log(Math.round(p.x), Math.round(p.y));
