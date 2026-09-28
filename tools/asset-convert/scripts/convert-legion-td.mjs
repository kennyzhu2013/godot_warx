#!/usr/bin/env node
/**
 * 军团战争 TD 5.34c 地形所需贴图子集。地图主 tileset 是 Cityscape，混用 Outland 等地表；
 * TerrainArt 全量都是小贴图，整目录转，避免漏掉混用的地表。
 * 军团自定义单位模型在地图 MPQ 里，不在这里，见 基于godot_war3实现军团战争.md §2.1。
 */
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pkg = path.resolve(__dirname, "..");

const includes = [
  // 地表 / 悬崖 / 水
  "TerrainArt/**",
  "ReplaceableTextures/Cliff/**",
  "ReplaceableTextures/Water/**",
  "ReplaceableTextures/Splash/**",
  "Textures/ShorelineParticleXY.blp",
  "Textures/White_64_Foam1.blp",
  // 悬崖模型：Wc3CliffCatalog 按 Doodads/Terrain/{Cliffs|CityCliffs}/…{TAG}{n}.glb 探测，不读 .scn
  "Doodads/Terrain/CityCliffs/**",
  "Doodads/Terrain/Cliffs/**",
  // 装饰物
  "Doodads/Cityscape/**",
  "Doodads/Outland/**",
  "Doodads/Terrain/Cityscape/**",
  "Doodads/Terrain/Outland/**",
];

const extra = process.argv.slice(2);
const args = ["src/cli.js"];
for (const g of includes) {
  args.push("--include", g);
}
args.push(...extra);

console.log("convert-legion-td →", includes.length, "include globs");
const r = spawnSync(process.execPath, args, {
  cwd: pkg,
  stdio: "inherit",
  shell: false,
});
process.exit(r.status ?? 1);
