/**
 * 从解开的军团地图目录导出单位定义叠加层与模型映射（阶段 2）。
 *
 *   node src/export-legion-slk.js <地图目录> [--out <输出目录>]
 *   地图目录缺省读环境变量 LEGION_LOOSE_DIR；输出缺省 assets/map-parsed/legiontd。
 *
 * 输出：
 *   slk/Units/{unitUI,UnitBalance,UnitWeapons,UnitData,UnitAbilities}.json
 *     与 slk-exported 同构，Wc3DefStore.apply_overlay_dir 直接读。列名按原版 slk-exported 表头大小写对齐。
 *   legion_models.json
 *     legion_data 里每个 id（units / hires / waves / king）→ 模板单位、显示名、模型、图标，
 *     以及需要从地图目录转换的模型与图标清单（convert-legion-units.mjs 读）。
 *
 * 模板选取：legion_data/models.txt（id,template，可选手工表）> 地图里同 id > 地图里同名单位 > 表里的 model_id 列。
 */
import fs from "node:fs";
import path from "node:path";
import { REPO_ROOT, LEGION_PARSED_DIR, LEGION_DATA_DIR } from "./legion-paths.js";
import { parseWts, resolveTrigStr } from "./parsers/wts.js";
import { parseSlk } from "../../slk-export/src/parse-slk.js";

const TABLES = [
  { file: "unitui.slk", out: "unitUI.json", key: "unitUIID" },
  { file: "unitbalance.slk", out: "UnitBalance.json", key: "unitBalanceID" },
  { file: "unitweapons.slk", out: "UnitWeapons.json", key: "unitWeapID" },
  { file: "unitdata.slk", out: "UnitData.json", key: "unitID" },
  { file: "unitabilities.slk", out: "UnitAbilities.json", key: "unitAbilID" },
];

/** 原版 slk-exported 缺失时的列名兜底（只列 Godot 侧会读的大小写敏感列）。 */
const FALLBACK_HEADERS = [
  "unitUIID", "unitBalanceID", "unitWeapID", "unitID", "unitAbilID",
  "HP", "realHP", "Primary", "STR", "AGI", "INT", "STRplus", "AGIplus", "INTplus",
  "RngBuff1", "RngBuff2", "RngTst", "RngTst2", "Farea1", "Harea1", "Qarea1", "Hfact1", "Qfact1",
  "DmgUpg", "DPS", "InBeta", "comment(s)",
];

function argValue(flag) {
  const i = process.argv.indexOf(flag);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function findChild(dir, name) {
  if (!dir || !fs.existsSync(dir)) return null;
  const hit = fs.readdirSync(dir).find((n) => n.toLowerCase() === name.toLowerCase());
  return hit ? path.join(dir, hit) : null;
}

/** 地图目录下按逻辑路径找文件，大小写不敏感。 */
function findLogical(root, logical) {
  let cur = root;
  for (const part of logical.replace(/\\/g, "/").split("/").filter(Boolean)) {
    cur = findChild(cur, part);
    if (!cur) return null;
  }
  return cur;
}

function stripModelExt(p) {
  return p.replace(/\.(mdx|mdl)$/i, "");
}

function normalizeLogical(p) {
  return String(p ?? "").replace(/\\/g, "/").replace(/^\/+/, "").trim();
}

/** WC3 颜色码与空白去掉后比较名字。 */
function plainName(s) {
  return String(s ?? "")
    .replace(/\|c[0-9a-f]{8}/gi, "")
    .replace(/\|r/gi, "")
    .replace(/\s+/g, "")
    .trim();
}

function canonicalHeaderMap(outName) {
  const map = new Map();
  for (const h of FALLBACK_HEADERS) map.set(h.toLowerCase(), h);
  const vanilla = path.join(REPO_ROOT, "assets", "slk-exported", "Units", outName);
  if (fs.existsSync(vanilla)) {
    try {
      const data = JSON.parse(fs.readFileSync(vanilla, "utf8"));
      for (const h of data.headers ?? []) map.set(String(h).toLowerCase(), String(h));
    } catch {
      // 原版表坏了就只用兜底列名
    }
  }
  return map;
}

function canonicalizeRecords(records, headerMap) {
  return records.map((rec) => {
    const out = {};
    for (const [k, v] of Object.entries(rec)) out[headerMap.get(k.toLowerCase()) ?? k] = v;
    return out;
  });
}

/** units/*.txt 与 war3mapskin.txt 的 ini 段 → { id: { key: value } }。 */
function parseIniInto(text, out) {
  let section = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/^\uFEFF/, "").trim();
    if (!line || line.startsWith("//") || line.startsWith(";")) continue;
    const sec = /^\[(.+)\]$/.exec(line);
    if (sec) {
      section = sec[1].trim();
      if (!out[section]) out[section] = {};
      continue;
    }
    if (!section) continue;
    const eq = line.indexOf("=");
    if (eq <= 0) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) value = value.slice(1, -1);
    out[section][key] = value;
  }
}

function iniGet(sec, key) {
  if (!sec) return "";
  const want = key.toLowerCase();
  for (const [k, v] of Object.entries(sec)) if (k.toLowerCase() === want) return v;
  return "";
}

function legionHeader(file) {
  const p = path.join(LEGION_DATA_DIR, file);
  if (!fs.existsSync(p)) return [];
  for (const raw of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const line = raw.trim();
    if (line && !line.startsWith("#")) return line.split(",").map((c) => c.trim());
  }
  return [];
}

function readLegionRows(file) {
  const p = path.join(LEGION_DATA_DIR, file);
  if (!fs.existsSync(p)) return [];
  let header = null;
  const rows = [];
  for (const raw of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const cols = line.split(",").map((c) => c.trim());
    if (!header) {
      header = cols;
      continue;
    }
    const row = {};
    header.forEach((h, i) => {
      row[h] = cols[i] ?? "";
    });
    rows.push(row);
  }
  return rows;
}

function main() {
  const mapDir = path.resolve(process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : process.env.LEGION_LOOSE_DIR ?? "");
  const outDir = path.resolve(argValue("--out") ?? LEGION_PARSED_DIR);
  if (!fs.existsSync(mapDir)) {
    console.error("地图目录不存在:", mapDir, "（参数或 LEGION_LOOSE_DIR）");
    process.exit(1);
  }
  const unitsDir = findChild(mapDir, "units");
  if (!unitsDir) {
    console.error("地图目录下没有 units/，不是 slk 优化后的解包目录:", mapDir);
    process.exit(1);
  }

  const slkOut = path.join(outDir, "slk", "Units");
  fs.mkdirSync(slkOut, { recursive: true });
  /** @type {Record<string, Map<string, Record<string, unknown>>>} */
  const tables = {};
  for (const t of TABLES) {
    const src = findChild(unitsDir, t.file);
    tables[t.out] = new Map();
    if (!src) {
      console.warn(`跳过 ${t.file}：地图里没有`);
      continue;
    }
    const parsed = parseSlk(fs.readFileSync(src));
    const headerMap = canonicalHeaderMap(t.out);
    const headers = parsed.headers.map((h) => headerMap.get(h.toLowerCase()) ?? h);
    const records = canonicalizeRecords(parsed.records, headerMap).filter((r) => String(r[t.key] ?? "").trim());
    for (const r of records) tables[t.out].set(String(r[t.key]).trim(), r);
    fs.writeFileSync(
      path.join(slkOut, t.out),
      `${JSON.stringify({ source: `map:units/${t.file}`, headers, recordCount: records.length, records }, null, 2)}\n`,
      "utf8",
    );
    console.log(`OK  units/${t.file} → slk/Units/${t.out}  ${records.length} 行`);
  }

  let wts = {};
  const wtsFile = findChild(mapDir, "war3map.wts");
  if (wtsFile) wts = parseWts(fs.readFileSync(wtsFile));
  /** @type {Record<string, Record<string, string>>} */
  const ini = {};
  for (const n of fs.readdirSync(unitsDir)) {
    if (n.toLowerCase().endsWith(".txt")) parseIniInto(fs.readFileSync(path.join(unitsDir, n), "utf8"), ini);
  }
  const skin = findChild(mapDir, "war3mapskin.txt");
  if (skin) parseIniInto(fs.readFileSync(skin, "utf8"), ini);

  const ui = tables["unitUI.json"];
  const mapNames = new Map();
  for (const id of ui.keys()) {
    const name = plainName(resolveTrigStr(iniGet(ini[id], "Name"), wts));
    if (name) mapNames.set(id, name);
  }

  const manualRows = readLegionRows("models.txt");
  const manualHeader = manualRows.length ? Object.keys(manualRows[0]) : legionHeader("models.txt");
  if (manualHeader.length && !manualHeader.includes("template")) {
    console.warn("WARN legion_data/models.txt 第一行非注释行必须是表头 id,template，本次忽略该表");
  }
  const manual = new Map(manualRows.filter((r) => "template" in r).map((r) => [r.id, r.template]));
  const nameIndex = new Map();
  for (const [id, n] of mapNames) if (!nameIndex.has(n)) nameIndex.set(n, id);

  function pickTemplate(id, name, modelId) {
    if (manual.get(id)) return { template: manual.get(id), how: "models.txt" };
    if (ui.has(id)) return { template: id, how: "map-id" };
    const want = plainName(name);
    if (want && nameIndex.has(want)) return { template: nameIndex.get(want), how: "map-name" };
    if (want) {
      let best = null;
      for (const [mid, n] of mapNames) {
        if (n.includes(want) && (best === null || n.length < mapNames.get(best).length)) best = mid;
      }
      if (best) return { template: best, how: "map-name~" };
    }
    if (modelId) return { template: modelId, how: "model_id" };
    return { template: "", how: "none" };
  }

  const convertModels = new Set();
  const convertIcons = new Set();
  const units = {};
  const unmatched = [];
  const specs = [
    ...readLegionRows("units.txt").map((r) => ({ id: r.id, name: r.name, model: r.model_id, kind: r.kind || "unit" })),
    ...readLegionRows("hires.txt").map((r) => ({ id: r.id, name: r.name, model: r.model_id, kind: "hire" })),
    ...readLegionRows("waves.txt").map((r) => ({
      id: `w${String(r.wave).padStart(3, "0")}`,
      name: `第${r.wave}波`,
      model: r.model_id,
      kind: "wave",
    })),
    ...readLegionRows("king.txt").map((r) => ({ id: "lkng", name: "国王", model: r.model_id, kind: "king" })),
  ];
  for (const s of specs) {
    if (!s.id) continue;
    const { template, how } = pickTemplate(s.id, s.kind === "wave" || s.kind === "king" ? "" : s.name, s.model);
    const rec = ui.get(template);
    const file = normalizeLogical(rec?.file ?? "");
    const inMap = Boolean(rec);
    const modelOnDisk = file ? findLogical(mapDir, `${stripModelExt(file)}.mdx`) : null;
    const icon = normalizeLogical(resolveTrigStr(iniGet(ini[template], "Art"), wts)).split(",")[0];
    const iconOnDisk = icon ? findLogical(mapDir, icon) : null;
    if (modelOnDisk) {
      convertModels.add(path.relative(mapDir, modelOnDisk).replace(/\\/g, "/"));
      const portrait = findLogical(mapDir, `${stripModelExt(file)}_portrait.mdx`);
      if (portrait) convertModels.add(path.relative(mapDir, portrait).replace(/\\/g, "/"));
    }
    if (iconOnDisk) convertIcons.add(path.relative(mapDir, iconOnDisk).replace(/\\/g, "/"));
    units[s.id] = {
      kind: s.kind,
      name: s.name,
      template,
      how,
      in_map: inMap,
      map_name: mapNames.get(template) ?? "",
      file,
      model_in_map_dir: Boolean(modelOnDisk),
      icon: icon ? icon.replace(/\.blp$/i, ".png") : "",
    };
    if (!template || how === "none") unmatched.push(`${s.id} ${s.name}`);
  }

  const kingCandidates = [];
  for (const [id, n] of mapNames) if (/国王|王者|King/i.test(n)) kingCandidates.push(`${id} ${n}`);

  const out = {
    version: 1,
    exportedAt: new Date().toISOString(),
    mapDir,
    units,
    convert: { models: [...convertModels].sort(), icons: [...convertIcons].sort() },
    kingCandidates,
  };
  fs.writeFileSync(path.join(outDir, "legion_models.json"), `${JSON.stringify(out, null, 2)}\n`, "utf8");

  const byHow = {};
  for (const u of Object.values(units)) byHow[u.how] = (byHow[u.how] ?? 0) + 1;
  console.log(`\nlegion_models.json：${Object.keys(units).length} 个 id，模板来源`, byHow);
  console.log(`需从地图目录转换：模型 ${convertModels.size}，图标 ${convertIcons.size}`);
  if (unmatched.length) console.log(`没有模板（将用胶囊体）：\n  ${unmatched.join("\n  ")}`);
  if (kingCandidates.length) {
    console.log(`地图里名字像国王的单位（可写进 king.txt 的 model_id）：\n  ${kingCandidates.join("\n  ")}`);
  }
}

main();
