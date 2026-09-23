/**
 * 解析已解开的地图目录（不是 MPQ）。输出与 parse-map.js 相同的 JSON。
 * node src/parse-loose.js <地图目录> --out <输出根目录>
 */
import fs from "node:fs";
import path from "node:path";
import { parseWts } from "./parsers/wts.js";
import { parseW3i } from "./parsers/w3i.js";
import { parseW3e } from "./parsers/w3e.js";
import { parseDoodadsDoo } from "./parsers/doo-doodads.js";
import { parseUnitsDoo } from "./parsers/doo-units.js";
import { parseW3r } from "./parsers/w3r.js";
import { parseWpm } from "./parsers/wpm.js";

const mapDir = path.resolve(process.argv[2] ?? "");
const outIdx = process.argv.indexOf("--out");
const outRoot = path.resolve(
  outIdx >= 0 ? process.argv[outIdx + 1] : path.resolve("..", "..", "assets", "map-parsed"),
);
const slug = "legiontd";
const outDir = path.join(outRoot, slug);

if (!fs.existsSync(mapDir)) {
  console.error("地图目录不存在:", mapDir);
  process.exit(1);
}

fs.mkdirSync(outDir, { recursive: true });

function read(name) {
  const hit = fs.readdirSync(mapDir).find((n) => n.toLowerCase() === name.toLowerCase());
  if (!hit) return null;
  return fs.readFileSync(path.join(mapDir, hit));
}

function writeJson(file, data) {
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}

const errors = {};
let strings = {};
const wts = read("war3map.wts");
if (wts) {
  strings = parseWts(wts);
  writeJson(path.join(outDir, "strings.json"), { count: Object.keys(strings).length, strings });
}

let info = null;
try {
  info = parseW3i(read("war3map.w3i"), strings);
  writeJson(path.join(outDir, "info.json"), info);
} catch (e) {
  errors.info = String(e);
}

let terrain = null;
try {
  terrain = parseW3e(read("war3map.w3e"), { includeTilepoints: false });
  const { tilepoints, heightfield, ...terrainMeta } = terrain;
  writeJson(path.join(outDir, "terrain.json"), terrainMeta);
  if (heightfield) {
    writeJson(path.join(outDir, "terrain-heightfield.json"), {
      tilepointWidth: terrain.tilepointWidth,
      tilepointHeight: terrain.tilepointHeight,
      mapWidth: terrain.mapWidth,
      mapHeight: terrain.mapHeight,
      centerOffset: terrain.centerOffset,
      mainTileset: terrain.mainTileset,
      mainTilesetName: terrain.mainTilesetName,
      groundTilesets: terrain.groundTilesets,
      cliffTilesets: terrain.cliffTilesets,
      tileSize: heightfield.tileSize,
      heights: heightfield.heights,
      groundTextures: heightfield.groundTextures,
      groundVariations: heightfield.groundVariations,
      cliffVariations: heightfield.cliffVariations,
      cliffTextures: heightfield.cliffTextures,
      layerHeights: heightfield.layerHeights,
      waterHeights: heightfield.waterHeights,
      flagsPacked: heightfield.flagsPacked,
    });
  }
  void tilepoints;
} catch (e) {
  errors.terrain = String(e);
}

let units = null;
try {
  const buf = read("war3mapUnits.doo");
  if (buf && buf.length > 16) {
    units = parseUnitsDoo(buf);
    writeJson(path.join(outDir, "units.json"), units);
  }
} catch (e) {
  errors.units = String(e);
}

let doodads = null;
try {
  doodads = parseDoodadsDoo(read("war3map.doo"));
  writeJson(path.join(outDir, "doodads.json"), doodads);
} catch (e) {
  errors.doodads = String(e);
}

let regions = null;
try {
  const buf = read("war3map.w3r");
  if (buf) {
    regions = parseW3r(buf);
    writeJson(path.join(outDir, "regions.json"), regions);
  }
} catch (e) {
  errors.regions = String(e);
}

let pathing = null;
try {
  pathing = parseWpm(read("war3map.wpm"));
  if (terrain?.centerOffset) {
    pathing.origin = { x: terrain.centerOffset.x, y: terrain.centerOffset.y };
  }
  const { _bytesRemaining, ...pathingOut } = pathing;
  writeJson(path.join(outDir, "pathing.json"), pathingOut);
  pathing._bytesRemaining = _bytesRemaining;
} catch (e) {
  errors.pathing = String(e);
}

const summary = {
  version: 1,
  parsedAt: new Date().toISOString(),
  sourceMap: mapDir,
  slug,
  map: info
    ? {
        name: info.name,
        author: info.author,
        playableWidth: info.playableWidth,
        playableHeight: info.playableHeight,
        players: info.players?.map((p) => ({
          playerNum: p.playerNum,
          name: p.name,
          type: p.typeName,
          race: p.raceName,
          startPosition: p.startPosition,
        })),
        forces: info.forces?.map((f) => ({ name: f.name, players: f.players })),
      }
    : null,
  terrain: terrain
    ? {
        mapWidth: terrain.mapWidth,
        mapHeight: terrain.mapHeight,
        centerOffset: terrain.centerOffset,
        stats: terrain.stats,
      }
    : null,
  units: units ? { count: units.count } : { count: 0 },
  doodads: doodads ? { count: doodads.count } : null,
  regions: regions ? { count: regions.count, names: regions.regions.map((x) => x.name) } : null,
  pathing: pathing ? { width: pathing.width, height: pathing.height } : null,
  errors: Object.keys(errors).length ? errors : undefined,
};
writeJson(path.join(outDir, "summary.json"), summary);
console.log(JSON.stringify(summary, null, 2));
console.log("OUT", outDir);
