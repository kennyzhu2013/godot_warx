#!/usr/bin/env node
/**
 * 军团单位模型与图标：从解开的地图目录（不是 MPQ）转进 assets/asset-converted（阶段 2）。
 *
 *   npm run convert:legion-units -- <地图目录> [--override-vanilla] [其它 cli.js 参数]
 *   地图目录缺省读 LEGION_LOOSE_DIR。
 *
 * 1. 跑 map-parse/src/export-legion-slk.js：写 map-parsed/legiontd/slk/**（单位定义叠加层）与 legion_models.json。
 * 2. 按 legion_models.json 的 convert 清单，从地图目录转模型（含 _portrait）与图标。
 *    输出放 asset-converted 而不是 mods/：地图模型的 glTF 外链原版贴图，同一棵目录里相对路径才对得上。
 *    地图里缺的贴图回退到原版解包根（ASSET_CONVERT_EXTRA_IN）。
 *    地图文件与原版同路径时默认跳过，避免盖掉原版产物；--override-vanilla 才转。
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { LEGION_PARSED_DIR } from "../../map-parse/src/legion-paths.js";
import { LEGACY_CACHE_ROOT, STAGING_ROOT } from "../../pipeline-paths.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pkg = path.resolve(__dirname, "..");
const exportScript = path.resolve(pkg, "..", "map-parse", "src", "export-legion-slk.js");

const argv = process.argv.slice(2);
const positional = argv[0] && !argv[0].startsWith("--") ? argv.shift() : undefined;
const mapDir = path.resolve(positional ?? process.env.LEGION_LOOSE_DIR ?? "");
const overrideVanilla = argv.includes("--override-vanilla");
const passthrough = argv.filter((a) => a !== "--override-vanilla");

if (!positional && !process.env.LEGION_LOOSE_DIR) {
  console.error("用法: npm run convert:legion-units -- <地图目录>（或设置 LEGION_LOOSE_DIR）");
  process.exit(1);
}
if (!fs.existsSync(mapDir)) {
  console.error("地图目录不存在:", mapDir);
  process.exit(1);
}

function run(args, env = process.env) {
  const r = spawnSync(process.execPath, args, { cwd: pkg, stdio: "inherit", shell: false, env });
  return r.status ?? 1;
}

function existsCaseless(root, logical) {
  let cur = root;
  for (const part of logical.split("/").filter(Boolean)) {
    if (!fs.existsSync(cur)) return false;
    const hit = fs.readdirSync(cur).find((n) => n.toLowerCase() === part.toLowerCase());
    if (!hit) return false;
    cur = path.join(cur, hit);
  }
  return true;
}

console.log("[1/3] 导出单位定义叠加层与模型映射");
if (run([exportScript, mapDir]) !== 0) process.exit(1);

const modelsFile = path.join(LEGION_PARSED_DIR, "legion_models.json");
const models = JSON.parse(fs.readFileSync(modelsFile, "utf8"));
const vanillaRoots = [STAGING_ROOT, LEGACY_CACHE_ROOT].filter((p) => fs.existsSync(p));

function pick(list) {
  const out = [];
  for (const logical of list ?? []) {
    const shadow = vanillaRoots.find((root) => existsCaseless(root, logical));
    if (shadow && !overrideVanilla) {
      console.log(`  跳过 ${logical}：与原版同路径（--override-vanilla 才转）`);
      continue;
    }
    out.push(logical);
  }
  return out;
}

const icons = pick(models.convert?.icons);
const mdx = pick(models.convert?.models);
const env = { ...process.env, ASSET_CONVERT_EXTRA_IN: vanillaRoots.join(path.delimiter) };
if (vanillaRoots.length === 0) {
  console.warn("  没有原版解包根（assets/.staging/wc3-assets）：地图里缺的贴图会变成红色占位");
}

let code = 0;
if (icons.length) {
  console.log(`[2/3] 图标 ${icons.length} 个`);
  const args = ["src/cli.js", "--in", mapDir, "--textures-only", "--skip-clean"];
  for (const g of icons) args.push("--include", g);
  code = run([...args, ...passthrough], env) || code;
} else {
  console.log("[2/3] 没有要从地图目录转的图标");
}
if (mdx.length) {
  console.log(`[3/3] 模型 ${mdx.length} 个`);
  const args = ["src/cli.js", "--in", mapDir, "--models-only", "--skip-clean"];
  for (const g of mdx) args.push("--include", g);
  code = run([...args, ...passthrough], env) || code;
} else {
  console.log("[3/3] 没有要从地图目录转的模型（全部借原版模板，或地图里没找到模型文件）");
}
process.exit(code);
