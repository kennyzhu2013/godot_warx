/**
 * 军团战争工具脚本共用路径。全部相对仓库根，不写本机绝对路径。
 * LEGION_PARSED_DIR 可覆盖已解析地图目录（默认 assets/map-parsed/legiontd）。
 */
import path from "node:path";
import { fileURLToPath } from "node:url";

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

export const LEGION_PARSED_DIR = path.resolve(
  process.env.LEGION_PARSED_DIR || path.join(REPO_ROOT, "assets", "map-parsed", "legiontd"),
);

export const LEGION_DATA_DIR = path.join(REPO_ROOT, "legion_data");
