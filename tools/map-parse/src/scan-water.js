import fs from "node:fs";
import path from "node:path";
import { LEGION_PARSED_DIR } from "./legion-paths.js";

const hf = JSON.parse(fs.readFileSync(path.join(LEGION_PARSED_DIR, "terrain-heightfield.json"), "utf8"));
const tw = hf.tilepointWidth;
const ox = hf.centerOffset.x;
const oy = hf.centerOffset.y;
let water = 0;
let cliff = 0;
let wmin = [1e9, 1e9];
let wmax = [-1e9, -1e9];
let cmin = [1e9, 1e9];
let cmax = [-1e9, -1e9];
const layers = new Map();
for (let i = 0; i < hf.flagsPacked.length; i += 1) {
  const tx = i % tw;
  const ty = Math.floor(i / tw);
  const x = ox + tx * 128;
  const y = oy + ty * 128;
  const layer = hf.layerHeights[i];
  layers.set(layer, (layers.get(layer) ?? 0) + 1);
  if (hf.flagsPacked[i] & 1) {
    water += 1;
    wmin = [Math.min(wmin[0], x), Math.min(wmin[1], y)];
    wmax = [Math.max(wmax[0], x), Math.max(wmax[1], y)];
  }
  if (layer !== 2) {
    cliff += 1;
    cmin = [Math.min(cmin[0], x), Math.min(cmin[1], y)];
    cmax = [Math.max(cmax[0], x), Math.max(cmax[1], y)];
  }
}
let inW = 0;
let inC = 0;
for (let i = 0; i < hf.flagsPacked.length; i += 1) {
  const tx = i % tw;
  const ty = Math.floor(i / tw);
  const x = ox + tx * 128;
  const y = oy + ty * 128;
  if (x < -7200 || x > 7200 || y < -1800 || y > 5800) continue;
  if (hf.flagsPacked[i] & 1) inW += 1;
  if (hf.layerHeights[i] !== 2) inC += 1;
}
console.log("water", water, wmin, wmax);
console.log("cliff", cliff, cmin, cmax);
console.log("inside view water", inW, "cliff", inC);
let dry = 0;
let dryAt = null;
for (let i = 0; i < hf.flagsPacked.length; i += 1) {
  if (hf.layerHeights[i] === 2 || (hf.flagsPacked[i] & 1)) continue;
  dry += 1;
  if (!dryAt) {
    const tx = i % tw;
    const ty = Math.floor(i / tw);
    dryAt = [ox + tx * 128, oy + ty * 128, hf.layerHeights[i]];
  }
}
console.log("dry cliff", dry, dryAt);
let shown = 0;
for (let i = 0; i < hf.flagsPacked.length && shown < 5; i += 1) {
  const tx = i % tw;
  const ty = Math.floor(i / tw);
  const x = ox + tx * 128;
  const y = oy + ty * 128;
  if (x < -7200 || x > 7200 || y < -1800 || y > 5800) continue;
  if ((hf.flagsPacked[i] & 1) === 0) continue;
  console.log("sample", i, "tx", tx, "ty", ty, "xy", x, y, "flag", hf.flagsPacked[i], "layer", hf.layerHeights[i]);
  shown += 1;
}
console.log("layers", [...layers.entries()].sort((a, b) => a[0] - b[0]));
