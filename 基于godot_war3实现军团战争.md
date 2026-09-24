# 基于 godot_war3 实现军团战争

> 目标：在 `godot_war3` 里做出可玩的《军团战争 TD》5.34c。镜头、底栏、模型、寻路、攻击和扣血都用这套引擎里已经在跑的魔兽对战。军团规则是一个独立的对局模式节点 `LegionMatchMode`，`GameDirector` 只负责选模式。
> 数值以同目录 [军团战争TD_5.34c_策划案.md](军团战争TD_5.34c_策划案.md) 为准。出怪表、基础伐木量、击杀赏金、国王坐标在策划案和地图数据里都未还原，实现时写成命名常量或自定表，文件头标明「自定规格」。
> 本文只定实现边界和阶段，不改游戏代码。

---

## 1. 结论

只做一个 Godot 工程：`Work\godot_war3`。军团局用继承场景 `game/scenes/legion_main.tscn`，从 `game_main.tscn` 继承，只覆盖导出参数：地图换成 `res://assets/map-parsed/legiontd`，关掉 Melee 开局，挂上 `LegionMatchMode`。`game_main.tscn` 保持 Echo Isles 人族对战不动。玩家看见的是现有 `GameHud`：金、木、人口、肖像、命令格、小地图。

权威状态留在引擎已有的对象上，军团只新增「阵营」和「回合」两份权威：

| 状态 | 权威 |
|------|------|
| 金、木、人口 | `PlayerStock`，`GameHud.bind_stock` 只读刷新 |
| 场上单位、国王 | `MapLoader.add_unit_instance` 摆出的单位，生命在单位自己的生命组件上 |
| 单位属性 | `Wc3DefStore`。军团四字码由对局开始时叠加的行提供（第 8 节） |
| 敌对 | 席位 → 阵营表（第 4 节）。`CombatQuery.is_hostile` 按阵营判定 |
| 回合与波次 | `LegionRoundClock`：准备 → 战斗 → 结算（第 6 节） |
| 移动 | `UnitNavigator` + `PathQuery`，区域内 A* + 攻击移动（第 7 节） |
| 出手、扣血、死亡 | `AttackController` → `DamagePipeline` → `DeathService`。飘字和弹道走现有 Present |
| 命令 | `CommandCard` + `CommandRouter`。造兵、点王、出售、雇怪是命令格上的动作 |

原图脚本在加密的 `war3map.bin` 里。本工程没有 JASS / Lua 宿主，不把 `.w3x` 丢进场景指望它自己跑。`map-parse` 已经把地形、路径、区域和开始点写成 `assets/map-parsed/legiontd`。玩法按策划案写在对局模式里，调上面这些接口。

人族 Melee 开局不跑：`MeleeBootstrap` 不会在出生点放主城和五个人类农民，也不会把库存设成 500 金 / 150 木。军团开局写进 `PlayerStock`：300 金、114 木、人口上限 7。

```text
策划案 + legion_data/*.txt + map-parsed/legiontd
        │
        ▼
legion_main.tscn → LegionMatchMode（独立节点，@export 注入依赖）
        │
        ├── LegionTables → Wc3DefStore 叠加行 / 本局伤害表
        ├── LegionSeats                    席位、阵营、区域、国王
        ├── LegionRoundClock               准备 / 战斗 / 结算
        ├── GameSession / PlayerStock      金木人口收入
        ├── CommandCard / CommandRouter    造兵、雇怪、点王、出售
        ├── MapLoader                      地形、摆单位、拆单位
        ├── UnitNavigator / PathQuery      区域内走路、吸地
        ├── AttackController
        │     DamagePipeline
        │     DeathService                 攻击、扣血、死亡
        └── GameHud                        底栏只读这些状态
```

---

## 2. 工程怎么接

| 角色 | 路径 |
|------|------|
| 对战工程 | `d:\game2\rpg\mpqediten64\Work\godot_war3` |
| Echo 人族对战 | `game/scenes/game_main.tscn`，不改 |
| 军团场景 | `game/scenes/legion_main.tscn`，继承 `game_main.tscn` |
| 军团入口 | `legion_ui/legion_boot.gd` 跳到 `legion_main.tscn` |
| 地图 | `assets/map-parsed/legiontd` |
| 军团表 | `legion_data/`（`armor.txt`、`units.txt`、`hires.txt`、`waves.txt`、`king.txt`、`cells.txt`、`lanes.txt`、`starts.txt`，新增 `seats.txt`） |
| 本文与策划案 | 仓库根目录 |

`legion_main.tscn` 覆盖的导出参数：

| 参数 | 值 |
|------|----|
| `map_dir` | `res://assets/map-parsed/legiontd` |
| `spawn_melee_base` | `false` |
| `dev_spawn_archmage` / `dev_spawn_priest` | `false` |
| `random_start_location` | `false` |

`place_units` 保持关闭：`war3mapUnits.doo` 单位数是 0，场上单位只由对局模式生成。镜头用现有 `rts_camera.gd`，开局 `focus_on_position` 对准本方 `RctPlayer` 区域中心，不用 `starts.txt` 的开始点（开始点在地图中部，建造区在 x≈±6200）。

`GameDirector` 已有 5000 行，`NEXT.md` N0 里本来就有瘦身项。军团规则不写进 `GameDirector`，它只加一处：场景里有 `LegionMatchMode` 时跳过 Melee 开局，地图加载完成后把 session、router、map_root 交给模式节点。

### 2.1 数据可复现（阶段 0 前置）

`assets/map-parsed/**` 和 `assets/asset-converted/**` 都不入库。现在换一台机器跑不出军团图：

- `tools/bootstrap.config.json` 的 `maps.items` 没有 legiontd。
- `tools/map-parse/src/` 下 `analyze-legion.js`、`grid-legion.js`、`write-legion-grid.js`、`lane-scan.js`、`scan-water.js` 写死了 `d:/game2/...` 绝对路径。
- `convert.include` 只含原版 `Units/**`、`Buildings/**`，没有地图 MPQ 里的自定义模型。

要做到：`bootstrap` 一条命令生成 `map-parsed/legiontd` 和军团模型。脚本路径改为相对仓库根或读 `bootstrap.config.json`。地图 MPQ 的资源走现有 mod overlay 车道（`AssetProvider.register_overlay`，目录 `mods/legiontd/`），见 `docs/architecture/ASSET_LANES.md`。

现状：

- 已做：军团脚本共用 `tools/map-parse/src/legion-paths.js`，不再写死本机路径；`LEGION_PARSED_DIR` 可覆盖已解析目录。
- 已做：`bootstrap.config.json` 有 `LegionTD` 条目，读已解包的地图目录。先把加密 w3x 解包，然后 `set LEGION_LOOSE_DIR=<解包目录>` 再跑 `node tools/bootstrap.mjs`；没设置时这一项跳过，不中断其它地图。也可以单跑 `node tools/map-parse/src/parse-loose.js <解包目录>`。
- 未做：军团模型进 mod overlay，放到阶段 2 之前。

验收只看游戏窗口：底栏数字、命令格、场上模型和血条。

---

## 3. 分层归属

按 `docs/architecture/LAYERED_ARCHITECTURE.md`，新增代码先说清层别。军团模式目录 `game/scripts/modes/legion/`，按层分文件，不做一个大脚本。

| 层 | 内容 | 说明 |
|----|------|------|
| Data | `LegionTables`：读 `legion_data/*.txt`，中文枚举映射到 SLK 键，生成 `UnitBalanceDef` / `UnitWeaponsDef` 行 | 逻辑层不出现「普通」「轻甲」这类中文字符串 |
| Data | `Wc3DefStore` 增加按对局叠加行的公开入口 | 不叠加时 Echo 行为不变 |
| Catalog | 军团四字码 → 模型路径 | 复用 `Wc3IdCatalog` + mod overlay，不在 Logic 里拼路径 |
| Logic | `LegionSeats`、`LegionRoundClock`、`LegionSpawner`、`LegionEconomy`、`LegionSellPolicy`、`LegionHirePolicy`、`LegionKing` | 无 Mesh；只调 `PlayerStock`、`CommandRouter`、`MapLoader` 公开 API |
| Logic | `CombatDamageTable` 支持本局倍率表；`CombatQuery.is_hostile` 支持阵营 | 两处都是对现有模块的小改，默认值保持 TFT 与按 owner |
| Presentation | 底栏收入 / 波次 / 回合倒计时；建造格高亮 | 只读 Logic 状态 |
| Editor | 不涉及 | 看图可以开编辑器，笔刷不进对局 |

---

## 4. 席位与阵营（先定死再写代码）

明文是 10 个建造席：左路 4 人 + 1 电脑，右路 4 人 + 1 电脑。胜利条件是打死对方国王（每边一座）。每位玩家有自己的国王三围科技和自己的收入。

地图数据对不上的地方：

- `RctPlayer_0..7` 是 8 个建造区域；`starts.txt` 有 10 个开始点，多数 `region` 是 `NONE`。
- `war3mapUnits.doo` 没有国王，`lanes.txt` 头注释写明「国王坐标对不上，折线不标国王」。

所以新增一张自定表 `legion_data/seats.txt`，把席位的所有对应关系写在一处，其它模块只查这张表：

```text
# 自定规格。区域来自 w3r；出怪点、漏怪点、国王坐标人工标定，阶段 1 在窗口里核对。
seat,side,region,spawn_x,spawn_y,leak_x,leak_y,king_x,king_y
0,L,RctPlayer_0,...
...
8,L,NONE,...      # 电脑席，持有左国王
9,R,NONE,...      # 电脑席，持有右国王
```

阵营规则：

- **敌对按阵营。** `CombatQuery.is_hostile` 现在只看 owner 是否相同。军团局注入「席位 → 阵营」，同阵营不敌对。没有注入时（Echo 对战）行为不变。
- **系统怪的 owner 是进攻方电脑席。** 打左路的系统怪归右电脑席（9），打右路的归左电脑席（8）。不用中立 owner：中立怪和雇兵 owner 不同，会在同一条路上互打。
- **雇兵归雇主。** 雇主和进攻方电脑席同阵营，所以雇兵和系统怪是友军，一起打对面。
- **一座阵营国王。** 左右各一个国王单位，归本阵营电脑席。5 名建造者的生命 / 攻击 / 恢复加成累加到这座国王上。+3 收入只进购买者自己的 `PlayerStock`。策划案写「可控制国王」，第一版国王不可选中，后做。
- **电脑席是建造者**，不是国王的替身。电脑席第一版空置；后做时只通过 `CommandRouter` 下和玩家相同的命令。站位对照 `Work/aipool` 的回放，回放不是行为树。
- **可玩切片按这个顺序加席：** 1v1（席位 0 对 4，两座国王）直到坐标、回合和伐木在窗口里验收通过；然后 2v2；最后 4v4 加两个电脑席。扩席只改 `seats.txt` 的启用行，不另做场景。

---

## 5. 规则写在哪

规则都在 `game/scripts/modes/legion/` 的 Logic 文件里，调用第 1 节的现成接口。数值表放在 `legion_data/`。

**按策划案要落地的**

- 开局 300 金 / 114 木，写入 `PlayerStock`。开局收入 5 是原型常量，策划案没有明文。
- 国王强化：80 木、+3 永久收入。生命、攻击、恢复分开加，数值读 `king.txt`。花木走 `PlayerStock.try_spend`，属性加在国王单位上。
- 雇怪：本回合准备阶段入队，下一个战斗回合开始时在对方区域出怪点刷出一次（策划案 2：「回合开始前召唤的怪只在下一回合出现一次」），并按 `hires.txt` 立刻给自己加收入。
- 出售：本回合建造的单位退 100% 投入金币，旧单位退 50%。投入 = 这条升级链上累计花的金币，不是当前这一阶的造价。退款走 `PlayerStock.add_gold`，单位走 `remove_unit_instance`。
- 兵力：普通单位 = 累计投入金币。英雄兵力 = 等级 × 25。英雄单位后做。
- 农场人口取在场农场的 `food_cap` 最大值，升级是替换同一格建筑，并改 `PlayerStock.food_cap`。
- 攻防倍率读 `legion_data/armor.txt`，装进本局伤害表，仍由 `DamagePipeline` 扣血（第 8 节）。
- `waves.txt` 有 30 行，并带 `force` 列，供出售保护读取。这张表是自定曲线，不是 5.34c 原表。

**先写成命名常量，文件头标明自定规格**

| 常量 | 取值 | 含义 |
|------|------|------|
| 准备时长 | 15 秒 | 原图准备时长未还原 |
| 战斗超时 | 90 秒 | 兜底，避免漏怪卡住回合 |
| 测试局波数 | 10 | 回放常见 30–33 波。打通后再拉到表里的 30 行 |
| 开局收入 | 5 | 明文未给出 |
| 开局人口上限 | 7 | 策划案写主城提供 7 |
| 国王初始生命 | 2000 | 明文未还原，写在 `king.txt` |
| 国王坐标、出怪点、漏怪点 | 见 `seats.txt` | 地图里没有，人工标定 |
| 玩家数 | 先 1v1 | 扩席见第 4 节 |

国王回复只在战斗中每秒加一次，加在国王单位的生命上，封顶为最大生命。回合结算不再加第二次。

木材目前表上只有开局的 114。伐木是阶段 4a 的第一项：小精灵是场上单位，到点给 `PlayerStock.add_lumber`。没有这一项时，雇怪和点王在第一波之后就会停。

---

## 6. 回合结构

`LegionRoundClock` 是回合的唯一权威，底栏倒计时和波次只读它。

```text
准备（15 秒） ── 到时 ──▶ 战斗 ── 结束条件 ──▶ 结算 ──▶ 下一波准备
```

**准备**

- 可造兵、升级、出售、雇怪、点王、伐木科技。
- 防守兵是静止的：不索敌、不可被玩家下移动命令。

**战斗**

- 系统怪按 `waves.txt` 的 `count` / `interval` 从每个启用席位的出怪点刷出；上回合入队的雇兵同时刷出。
- 怪对漏怪点下攻击移动；到漏怪点后对本阵营国王下攻击移动（第 7 节）。
- 防守兵自动索敌，不追出本区域（区域边界作 leash）。
- 国王每秒回复。

结束条件：本波系统怪和雇兵全部死亡，或战斗超时。超时时仍在场的进攻怪直接移除，不另算伤害。

**结算**

- 发放收入：`add_gold(income)`。
- 防守兵复位：回到建造格、回满血，本回合战死的重新摆出。防守兵在回合之间一直存在，出售和兵力计算依赖这一点。
- 回合计数 +1；到测试局波数或一方国王死亡时结束对局。

防守兵复位是 Legion TD 的通行机制，策划案里没有明文，阶段 3 用 `aipool` 回放核对。

每个防守兵在单位 meta 上记：`seat`、`cell`、`build_round`、`invested_gold`。复位、出售和兵力都读这四项。

---

## 7. 坐标与路线

地图大约宽一万，射程是 100–800。建造格、行军和射程从第一版就用魔兽坐标。

- **建造格：** `席位 → region → cell → WC3 XY`，已在 `legion_data/cells.txt`（8 个区域 × 9 列 × 16 行）。和路径图对不上时改格子划分，以可走、可造的空地为准。农场格单独标。
- **每个玩家的区域就是他的那条路。** 怪从区域上沿的出怪点刷出，向下走到漏怪点。区域内用现有 A* + `AttackController.start_attack_move(goal)`，不手写折线。
- **`lanes.txt` 不是出怪路线。** 它是 `RctPlayer` 区域之间扫出来的可走带（`mid_road`、`gap_*`）。阶段 1 只拿它核对漏怪点到国王之间是否连通。
- **漏怪：** 到漏怪点后对本阵营国王坐标攻击移动。`start_attack_move` 只收单个目标点，分两段下命令由 `LegionSpawner` 在 `arrived` 后接上。
- 移动速度用单位说明里的魔兽移速，由导航按秒积分。
- 射程用说明里的原始距离，交给 `CombatQuery` 的出手射程。
- 攻击间隔用武器表里的间隔秒。`AttackController` 的冷却已经按秒跑，说明里的攻击速度是间隔秒，不是每秒攻击次数。

出生点从 `map-parse` 的 `w3i` 读取，对照写在 `starts.txt`，只用于核对，不驱动相机和出怪。`war3map.j` 只是加密脚本入口，里面没有 `DefineStartLocation`。

---

## 8. 单位、属性和界面

对局模式在四个时机动单位：准备阶段玩家造出的兵、战斗开始刷出的系统怪和雇兵、结算时复位防守兵、进攻怪死亡或出售时移除。位置和生命就在单位节点上，导航和攻击控制器每帧自己更新。

`add_unit_instance` 要编辑器同款条目：

- `typeId`：单位四字码
- `position`：`{x, y, z}`，高度用当前高度图采样
- `angle`、`owner`
- `creationNumber`：供 `remove_unit_instance` 使用

建造是否合法只看格子占用和 `get_pathing_map` 的可造标记。造兵命令不走人类农民的工地和建造加速。

### 8.1 属性叠加

`AttackController`、`DamagePipeline`、`UnitNavigator`、血条都按四字码从 `Wc3DefStore` 查 `UnitBalanceDef` / `UnitWeaponsDef`。`Wc3DefStore` 现在只从 `slk-exported` 读一份，没有叠加入口；`h010`、`m080` 这类军团 ID 查不到。

做法：

1. `Wc3DefStore` 加公开方法，按表名叠加一组行（同主键覆盖），并能清除本局叠加。
2. 对局开始时 `LegionTables` 把 `units.txt`、`hires.txt`、`waves.txt` 转成行叠加进去。
3. 系统怪没有四字码，按波次分配合成 ID（`w001`–`w030`），模型在 `waves.txt` 加一列 `model_id` 指向已有单位。

这样战斗、导航、血条都不用改。

### 8.2 本局伤害表

`CombatDamageTable._TFT` 是常量，`multiplier` 是静态方法，没有换表的挂点。改为：默认仍是 TFT 表；军团模式开局装入 `armor.txt` 换算出的倍率，对局结束清掉。

`armor.txt` 的中文名在 `LegionTables` 里映射到 SLK 键：

| 护甲 | SLK defType | 攻击 | SLK atkType |
|------|-------------|------|-------------|
| 轻甲 | small | 普通 | normal |
| 中甲 | medium | 穿刺 | pierce |
| 重甲 | large | 攻城 | siege |
| 魂甲（原 Fortified） | fort | 魔法 | magic |
| 城甲（原 Normal） | normal | 法术 | spells |
| 英雄 / 国王 / 王甲 | hero | 混乱 | chaos |
| 神圣 | divine | 国王 | hero |
| 无甲 | none | | |

`_TFT` 现在没有 `normal` 护甲列，默认 1.0；军团表会补齐。

### 8.3 模型与底栏

模型经 `tools/asset-convert` 把 MDX 烤成 `.scn`。先转 `units.txt`、`hires.txt` 和 `waves.txt` 的 `model_id` 里出现的单位。这些模型在地图 MPQ（`Work/`）里，不在魔兽原版资源里，走 mod overlay（第 2.1 节）。底栏继续用 `GameHud` 和 `CommandCard`。收入、当前波次和回合倒计时加在现有资源条旁，由 `PlayerStock` 和 `LegionRoundClock` 驱动。

弹道和飘字由 `DamagePipeline.damage_applied` 和 `ProjectileService` 播放，和人族对战同一条线。

### 8.4 军团 GM 面板

验收全在窗口里做。在现有 GM 面板（`GameDirector._ensure_gm_panel`）上加一页军团按钮：

- 跳到第 N 波；立即开战；立即结算
- 加金 / 加木
- 显示建造格、出怪点、漏怪点、国王坐标
- 显示每个单位的 seat / 阵营 / owner

---

## 9. 阶段

编号即顺序。前一阶段在游戏窗口里验收通过，再开下一阶段。

### 阶段 0 · 用军团地图开一局

前置：第 2.1 节的数据可复现。

新建 `legion_main.tscn`，`legion_boot.gd` 跳到它。跳过 `MeleeBootstrap`。本地 `PlayerStock` 设为 300 金、114 木、人口 0/7。相机对准本方 `RctPlayer` 区域。

**验收：** 窗口里是军团地图的地形，顶栏是 300 金、114 木、人口 0/7。没有人族主城，没有五个农民。另开 `game_main` 仍是 Echo Isles 500 金 / 150 木。

已接好：`MatchMode` 基类（`game/scripts/modes/match_mode.gd`）；`GameDirector.match_mode` 绑定后由模式建 session 并跳过 Melee，`session_ready` 后调 `begin`；`LegionMatchMode` 设库存、镜头对准 `local_region`（默认 `RctPlayer_0`）的格子中心，状态行写出区域和库存；`LegionTables` 读 `legion_data`；`legion_main.tscn` 继承 `game_main`。

验收步骤：编辑器打开项目一次（注册新的 `class_name`），F6 运行 `game/scenes/legion_main.tscn` 或 `legion_ui/legion_boot.tscn`，对照上面的验收；再 F6 `game_main.tscn` 确认 Echo 不受影响。

### 阶段 1 · 地图对位与席位表

不刷波、不造兵。写出 `seats.txt`，用 GM 面板把建造格、出怪点、漏怪点、国王坐标画出来。

**验收**

- 游戏窗口里悬崖、水和路可辨认。
- 点一个建造格，状态行坐标与 `cells.txt` 一致。
- 出怪点、漏怪点、国王坐标都在可走格上；漏怪点到国王连通。

### 阶段 2 · 造兵、阵营、走路、国王

1v1。命令格提供「造当前兵」「强化国王生命」「出售」。造兵在格子上立刻出现模型，并扣 `PlayerStock`。军团单位属性由 `Wc3DefStore` 叠加行提供。阵营表注入 `CombatQuery`。系统怪从出怪点走到漏怪点，再走到国王面前。国王血条就是该单位的生命。

**验收：** 在窗口里造一个兵、点一次国王、卖掉刚造的兵，底栏金币和国王血条与这三次操作一致。怪能走到国王附近。GM 面板显示系统怪 owner 是对方电脑席。

### 阶段 3 · 回合循环与战斗

`LegionRoundClock` 跑通准备 → 战斗 → 结算。怪和己方兵用 `AttackController` 索敌、按射程出手。`DamagePipeline` 用本局伤害表扣 `UnitLife`。进攻怪死亡走 `DeathService`，播死亡动画后 `remove_unit_instance`。防守兵战死只播动画，结算时复位。结算发放收入。国王每秒回复只加在战斗阶段。

**验收：** 窗口里能看见攻击、掉血飘字和死亡。漏到国王的怪在打国王，国王血条下降。回合结束后防守兵回到原格满血，战死的重新出现，金币增加一次收入。连续打 3 波不卡回合。

### 阶段 4a · 经济

每条都在游戏窗口里单独能看出来。

1. **伐木。** 小精灵是单位，上限 7。普通模式每 10 秒结算一次。1–8 级每个小精灵每次 +1，9 级起 +2。基础每次采集量明文没有，命名为 `LUMBER_BASE`，默认 1，写在 `legion_data/lumber.txt` 头上。造价以 `unitbalance.slk` 为准（公开攻略写 50 金，导入时核对）。开局 114 木是赠送。结算调用 `PlayerStock.add_lumber`。
2. **永久收入。** 回合发放等于当前收入，只增不减。雇怪收入在雇的当时已经加过，发放时不要再加一次。
3. **农场链。** 用策划案 5.2 的金、木、人口。开局人口上限 7。升级替换该格建筑，并改 `food_cap`。
4. **击杀赏金。** 公式未还原。`waves.txt` 增加 `bounty`，默认 0。击杀系统怪时 `add_gold(bounty)`，漏到国王不加这笔。

**验收：** 造小精灵并升一次伐木后木材按周期变多；升农场后人口上限变化；每回合金币按收入增加。

### 阶段 4b · 军团命令

1. **雇怪。** 雇一只 80 木怪，下一波出现在对方区域，雇主收入 +3。
2. **雇兵波次门。** 按策划案 5.4：280 木以下随时可雇；约 280–400 木在第 10 波之后；500 木及以上在第 15 波之后。命令格拒绝过早的高价木怪，并在状态行说明。
3. **出售保护。** 第 5 波后，每回合出售旧单位的兵力合计不超过 400，或允许卖掉 1 个单位。当前兵力低于本波 `waves.txt` 的 `force` 的一半时不能卖。第 10 波起不能卖到该 `force` 的 75% 以下。奴隶主、老兵、螯虾、虾皇、鼠群豁免。`force` 来自自定曲线，规则形状按策划案 5.8。拒绝时底栏状态行写出原因，金币不变。
4. **先知竞赛。** 第一条可玩模式。开局从该族抽可造单位（公开攻略是 6 个，次数与个数做成表，默认 6 个、最多预言 5 次）。第一次不耗木，之后按策划案 5.5 递增。开局不给整族科技树。抽到的单位显示在 `CommandCard` 上。
5. **英雄祭坛。** 100 金、12 人口，不占普通兵的升级链。兵力 = 等级 × 25。出兵走现有训练队列的同一套「花钱、占人口、生成单位」。光环先做策划案 8.5 里能写清数字的几条（护甲 +4、远程攻击 +28%、每秒回蓝 1.1 等），挂到现有 Buff。其余光环后做。

**验收：** 在窗口里走完「抽 6 个兵 → 造兵 → 雇一只 80 木怪 → 非法出售被拒绝 → 国王被击破或打满测试局波数」。

四路、2v2、4v4 放在 4a、4b 验收之后。扩席时只改 `seats.txt` 的启用行。

16 族全量树、变形、六倍怪、暴露速战的积分判胜再往后。族数据用策划案第 16 章，一次接一族，每族至少一条从 1 阶到封顶的升级链能在命令格里造出来。

### 阶段 5 · 打一局，以及明确不做

在窗口里打完固定的 10 波。记下每波怪数量、漏到国王的伤害、建造花费、出售返还、伐木净增、结束时国王生命。这些数都从底栏和国王血条读。

和魔兽录像对比时，只对比玩家造了什么、金币收支、国王血的方向，以及回合结束后防守兵是否复位。系统怪数量来自 `waves.txt`，和原图不同是预期。

六倍怪只采用明文写死的特例：14 波后雇怪收入减半向下取整；第 20 波 5 只、第 21 波 4 只。其余波次仍用自定曲线。这两条在阶段 4 之后单开模式，不塞进默认局。

不做：

- 反编译或移植 `war3map.bin` / JASS。
- DzAPI、商城、DzFrame、自定义平台 UI。
- 策划案第 10 章的外观指令和赞助权限。
- 另一套血量、冷却、收入或底栏。军团局只写 `PlayerStock`、单位生命和 `GameHud`。
- 人族采矿循环、农民工地、兵营训练队列、人类英雄技能接到这张图的开局上。
- 中央通道、加防区积分、暴露速战记分板。漏怪是「走到漏怪点再攻击国王」。

---

## 10. 数据从哪来

| 数据 | 来源 | 实现时怎么用 |
|------|------|----------------|
| 攻防克制 | 策划案第 4 章，`legion_data/armor.txt` | 映射到 SLK 键，装入本局伤害表 |
| 开局资源 | 策划案 5.7 | 写入 `PlayerStock`。开局收入 5 保持为原型常量 |
| 农场、主城人口 | 策划案 5.2 | 开局 `food_cap = 7`；农场按表改 `food_cap` |
| 造兵造价与战斗面板 | `unitbalance.slk` 的金木人口；HP / 攻击用单位说明，不用 SLK 里占位的 500 | 导入进 `units.txt`，开局叠加进 `Wc3DefStore` |
| 雇怪木价、收入、解锁波 | 策划案 5.4 | `hires.txt` 的 `income`、`min_wave` |
| 国王三围 | `king.txt` | 点王命令改国王单位属性 |
| 席位、阵营、出怪点、漏怪点、国王坐标 | 自定，阶段 1 标定 | `seats.txt` |
| 出售保护 | 策划案 5.8 | 阈值读 `waves.txt` 的 `force` |
| 兵力 | 累计投入金币；英雄等级 × 25 | 出售保护用，显示可加在底栏 |
| 伐木 | 策划案 5.1 的间隔和每级加成 | `LUMBER_BASE` 自定，默认 1 |
| 击杀赏金 | 未还原 | `waves.txt` 的 `bounty`，默认 0 |
| 系统怪曲线与外形 | 未还原 | `waves.txt`，加 `model_id`，文件头注明自定 |
| 技能 | 策划案 11.1 先做；11.2 不做 | 见第 11 节 |
| 格子、区域、开始点 | `map-parse` 的 w3i、w3r、wpm | `cells.txt`、`starts.txt`；`lanes.txt` 只作连通核对 |
| 电脑操作 | `Work/aipool` 回放 | 只对照站位；顺带核对防守兵复位 |

SLK 导入放在 `godot_war3/tools/`，沿用已经能读 `F;Y` / `F;X` 表头的解析，多出来的列写入 `legion_data` 的表。

---

## 11. 技能

11.1 里能对上数字的，加成一张效果表，挂到现有 Buff / 技能路径上，由 `DamagePipeline` 和 `BuffHost` 结算。效果种类先只做四种：持续伤害、减速、光环加减、死亡时治疗或伤害。乌头毒素、蛛网、淬毒标枪、甲胄、西里诺克斯之优雅、治愈之叶、禁忌之果走这张表。数值用策划案 11.1 的 Dur / Data。

11.2（跃迁、梦魇、鼠王随数量缩放、按波数反弹的荆棘）留空。单位说明里照样显示名字。

人族已经接好的暴风雪、水元素留在人族对战里。军团局的命令格只列出本局抽到的单位、雇怪、点王、出售和上面这张效果表里的技能。

---

## 12. 这张图用什么、不用什么

**用这些**

| 模块 | 作用 |
|------|------|
| `legion_main.tscn` / `LegionMatchMode` | 军团对局壳与规则 |
| `GameDirector` | 选模式、交出依赖 |
| `GameSession` / `PlayerStock` | 玩家与金木人口 |
| `Wc3DefStore` | 单位属性，本局叠加军团行 |
| `GameHud` / `CommandCard` | 底栏和命令 |
| `MapLoader` | 地形、`add_unit_instance` / `remove_unit_instance`、`get_pathing_map` |
| `UnitNavigator` / `PathQuery` / `rts_camera.gd` | 走路、吸地、镜头 |
| `CommandRouter` | 命令入口 |
| `AttackController` / `CombatQuery` | 索敌、出手、阵营敌对 |
| `DamagePipeline` / `CombatDamageTable` / `DeathService` | 唯一扣血、本局倍率、死亡 |
| `ProjectileService` / 飘字 | 攻击表现 |
| 选中环、血条 | 现有 Present |

**这张图的开局不调用**

| 模块 | 原因 |
|------|------|
| `MeleeBootstrap` | 会在出生点放主城和农民，并把库存设成 500 / 150 |
| 人族 `HarvestController` 的金矿循环 | 军团木材是小精灵定时结算，金币来自收入和赏金（策划案 3.1 的「金矿」待确认，见第 14 节） |
| 人族 `BuildSite` 工地 | 军团造兵是格子上立即生成，不派农民修建 |
| 人族兵营训练和顶盾科技 | 命令格的内容和人族科技树不同 |
| `TeamRegistry` 的野怪营地 leash | 军团怪不回营；防守兵用区域边界作 leash |
| `editor/` 笔刷 | 看图可以开编辑器，笔刷不进对局 |

人族这些模块留在 Echo Isles 对战里，不删。

---

## 13. 阶段 0 结束时要有的接法

```text
Work/godot_war3/
  game/scenes/game_main.tscn       不改，仍是 Echo Isles
  game/scenes/legion_main.tscn     继承 game_main，覆盖导出参数，挂 LegionMatchMode
  game/scripts/modes/legion/       军团对局模式，按第 3 节分层
  legion_ui/legion_boot.gd         跳到 legion_main
  legion_data/                     规则表、格子、席位
  mods/legiontd/                   地图 MPQ 资源 overlay（不入库，bootstrap 生成）
  assets/map-parsed/legiontd/      地形、路径、区域、开始点（不入库，bootstrap 生成）
```

阶段 0 只加场景、跳过 Melee、设 `PlayerStock`。属性叠加、阵营、伤害表从阶段 2 起接，回合循环从阶段 3 起接。

---

## 14. 待确认

| 问题 | 怎么确认 | 未确认前的默认 |
|------|----------|----------------|
| 防守兵每波后是否复位、战死是否复活 | `aipool` 回放 | 复位并复活 |
| 策划案 3.1 的「金矿」是什么 | 物体编辑器 / 说明文字 | 不做金矿 |
| 国王坐标、出怪点、漏怪点 | 窗口里对照地形标定 | `seats.txt` 自定 |
| 国王是否可控制、归谁 | 策划案第 6 章 + 回放 | 归本阵营电脑席，不可选中 |
| 雇兵在对方区域的刷出点 | 回放 | 与系统怪同一出怪点 |
