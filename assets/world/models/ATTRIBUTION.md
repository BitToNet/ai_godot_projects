# 世界模型署名与来源 / Attribution

本目录下的模型全部为 **CC0 1.0 Universal（公共领域贡献）**，可自由复制、修改、分发、商用，
**无需署名**。此处保留来源记录只为可追溯，不构成任何署名义务。

上游仓库只提供 **FBX**（`KayKit-Medieval-Hexagon-Pack` 里 0 个 `.glb` / `.gltf`），
本目录里的 `.glb` 是**参考项目已转换好、且贴图内嵌（GLB BIN 块）的成品**。
经用户 2026-10-14 明确授权（见 `docs/PORTING.md` §6 的豁免说明），本轮直接复用这批转换产物，
以免把「FBX → glTF 转换」这条与本轮目标无关的工具链引进来。
**授权范围仅限「读取并复制」这批 CC0 文件**：参考仓库仍是只读的，不得改动、不得提交其内容。

## 1. 建筑 —— Kay Lousberg (KayKit)

| 文件 | 字节 | SHA-256 | 三角形 | 许可 | 来源 |
|---|---|---|---|---|---|
| `bld_house_a.glb` | 72,552 | `aadc8fd5fcbeb24475c65b38a8e638f7f827e5d177282a0a14ebdfba39aa61cd` | 1011 | CC0 1.0 | 同下 |
| `bld_house_b.glb` | 99,324 | `3bc83821d2220d5054166a09e34f6cf07cc62bc9db071b0a635c5ccd76f844ce` | 1393 | CC0 1.0 | 同下 |
| `bld_well.glb` | 59,540 | `5a665d0ab641f545a57e02dd22f241daf415c7185c03555cab528f2b970211d2` | 726 | CC0 1.0 | 同下 |
| `bld_windmill.glb` | 160,684 | `dcf053564b3e4b2d6e91224b675b7215a9955db440763901cd51f3951762b2a7` | 2653 | CC0 1.0 | 同下 |

- 作者：**Kay Lousberg (KayKit)**
- 来源：<https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack>
- 许可：**CC0 1.0 Universal**

**贴图**：这 4 个文件都内嵌**同一张**图集（PNG，15,783 字节，SHA-256 前缀 `5301A06866BA3BE6…`）。
正因为图集一致，4 种建筑才能共用一个材质实例 ——
这条前提不靠假设，`tools/asset_check.gd` 会把它钉在门禁里。

## 2. 尚未入库的同类资产（仅登记，本轮不动）

同批 CC0 资产还有 `bld_keep` / `bld_wall` / `bld_tavern` / `bld_church` / `bld_market` /
`bld_barracks` / `bld_smith` / `bld_tent` / `bld_tower_large` / `bld_tower_small` /
`prop_tree_a` / `prop_tree_b` / `prop_rock_a` / `prop_rock_b`，以及
KayKit Character Pack Adventures 的 `unit_knight`、Quaternius 的坐骑。
它们分别属于第③批-3（城镇 / 城堡）与第④批（部队），**本轮不入库**。

## 3. 许可速查

| 许可 | 能否商用 | 是否必须署名 |
|---|---|---|
| CC0 1.0 | 可以 | 不需要 |