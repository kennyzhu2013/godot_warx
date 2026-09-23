import fs from "node:fs";
const root = "d:/game2/rpg/mpqediten64/Work/godot_war3/assets/map-parsed/legiontd";
const pathing = JSON.parse(fs.readFileSync(`${root}/pathing.json`, "utf8"));
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
function row(y) {
  let s = "";
  for (let x = -7000; x <= 7000; x += 128) {
    const f = flag(x, y);
    if (f < 0) s += "?";
    else if ((f & 2) !== 0) s += "#";
    else if ((f & 8) !== 0) s += ".";
    else s += "o";
  }
  console.log(String(y).padStart(6), s);
}
console.log("x from -7000 step 128. # nowalk  . walk nobuild  o walk+build");
for (const y of [1472, 2000, 2800, 4160, 128, -1408, 640]) row(y);
