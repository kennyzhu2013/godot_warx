import fs from "node:fs";

const root = "d:/game2/rpg/mpqediten64/Work/godot_war3/assets/map-parsed/legiontd";
const dataDir = "d:/game2/rpg/mpqediten64/godot/data";
const regions = JSON.parse(fs.readFileSync(`${root}/regions.json`, "utf8"));
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
function walkable(x, y) {
  const f = flag(x, y);
  return f >= 0 && (f & 2) === 0;
}

const rects = regions.regions
  .filter((r) => r.name.startsWith("RctPlayer_"))
  .sort((a, b) => a.name.localeCompare(b.name));

const cellLines = [
  "# 来源 war3map.w3r 的 RctPlayer_0..7，加上 war3map.wpm。",
  "# 每个区域 1152×2048，按 128 分成 9 列 × 16 行。抽查的 144 个中心点都可走且可造。",
  "# 不是模拟器里的 6×4。本文件先不接 CombatSim。",
  "# w3i 开始点与这些区域不是一一对应，见 starts.txt。",
  "region,col,row,x,y,walk,build",
];
let bad = 0;
for (const rg of rects) {
  const b = rg.bounds;
  for (let row = 0; row < 16; row += 1) {
    for (let col = 0; col < 9; col += 1) {
      const x = b.left + 64 + col * 128;
      const y = b.bottom + 64 + row * 128;
      const f = flag(x, y);
      const walk = f >= 0 && (f & 2) === 0 ? 1 : 0;
      const build = f >= 0 && (f & 8) === 0 ? 1 : 0;
      if (!walk || !build) bad += 1;
      cellLines.push(`${rg.name},${col},${row},${x},${y},${walk},${build}`);
    }
  }
}

const laneLines = [
  "# 来源 war3map.wpm 上 RctPlayer 区域之间的可走带。点都在可走格上。",
  "# war3mapUnits.doo 单位数为 0，国王坐标对不上，折线不标国王。方向不在明文里。",
  "# 本文件先不接 CombatSim。",
  "lane,i,x,y,walk",
];
function pushLane(name, points) {
  points.forEach((p, i) => {
    const w = walkable(p.x, p.y) ? 1 : 0;
    if (!w) bad += 1;
    laneLines.push(`${name},${i},${p.x},${p.y},${w}`);
  });
}
// 上下两排建造区之间的横路，y 取两排边界的中点。
const midY = 2816;
const road = [];
for (let x = -6208; x <= 6208; x += 256) {
  if (walkable(x, midY)) road.push({ x, y: midY });
}
pushLane("mid_road", road);
// 四列建造区之间的三条竖向空隙，各取中线。
const gaps = [
  ["gap_0_1", -3520],
  ["gap_1_2", 0],
  ["gap_2_3", 3520],
];
for (const [name, x] of gaps) {
  const pts = [];
  for (let y = 512; y <= 5120; y += 256) {
    if (walkable(x, y)) pts.push({ x, y });
  }
  pushLane(name, pts);
}

const startLines = [
  "# 来源 war3map.w3i 玩家开始点。区域来自修正后的 w3r（left, bottom, right, top）。",
  "# 八个 RctPlayer 与十个开始点对不上的，region 列写 NONE。不另编一套坐标。",
  "# 圣明军团的 force mask 是「除统影席位外的全部位」，含空槽 10–31。座位仍是 0–9。",
  "player,name,type,race,x,y,region",
];
for (const p of info.players) {
  const hits = rects.filter((rg) => {
    const b = rg.bounds;
    return p.startPosition.x >= b.left && p.startPosition.x <= b.right
      && p.startPosition.y >= b.bottom && p.startPosition.y <= b.top;
  });
  startLines.push([
    p.playerNum,
    p.name,
    p.typeName,
    p.raceName,
    p.startPosition.x,
    p.startPosition.y,
    hits.length ? hits.map((h) => h.name).join("|") : "NONE",
  ].join(","));
}

fs.writeFileSync(`${dataDir}/cells.txt`, `${cellLines.join("\n")}\n`, "utf8");
fs.writeFileSync(`${dataDir}/lanes.txt`, `${laneLines.join("\n")}\n`, "utf8");
fs.writeFileSync(`${dataDir}/starts.txt`, `${startLines.join("\n")}\n`, "utf8");
console.log("cells", cellLines.length - 5, "bad", bad);
console.log("lanes", laneLines.length - 4);
console.log("starts", startLines.length - 4);
console.log(startLines.slice(4).join("\n"));
