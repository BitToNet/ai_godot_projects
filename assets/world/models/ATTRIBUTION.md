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

## 1b. 部队（坐骑 + 骑手）—— 第④批入库

| 文件 | 字节 | SHA-256 |
|---|---|---|
| `mount_horse.glb` | 1,109,444 | `18e866e6ea2789701d0c1948bcedabe10dd0065507e15a1721d81b6fe61606b1` |
| `mount_horse_alt.glb` | 1,108,124 | `fae7a7ec91e0d6a33554efb896fac9c4e8c632644183bcb8cc962f673d3ce609` |
| `mount_donkey.glb` | 1,093,824 | `b3a529f300a3d2e62db7ac02f45df42327af9740146f0b27c5cae7b5d234f1d2` |
| `unit_knight.glb` | 3,659,532 | `60428e3abc09ba83e595d256e3af8c5c976b46cdae599f0802fc82b4a3445168` |
| 模型 | 三角形 | 许可 | 作者 | 来源 |
|---|---|---|---|---|
| `mount_horse.glb` / `mount_horse_alt.glb` / `mount_donkey.glb` | 2182 / 2182 / 2000 | CC0 1.0 | Quaternius | <https://poly.pizza/m/bEdE4rmZy9> · <https://poly.pizza/m/qvTrSG9pZF> · <https://poly.pizza/m/qmX6nhnvp7> |
| `unit_knight.glb` | 6952 | CC0 1.0 | Kay Lousberg (KayKit) | <https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0> |

- 授权同上：用户 2026-10-14 的明确授权（见 `docs/PORTING.md` §6），范围仍是**只读取并复制**
  这批 CC0 成品；参考仓库保持只读。
- 用途：`unit_knight.glb` 一物两用 —— 骑手（清单键 `rider_seated`，播 `Sit_Chair_Idle`）
  与步行单位（预留键 `party_foot`，播 `Walking_A` / `Idle`）；三匹坐骑播 `Gallop` / `Idle`。
- **落座高度不是抄来的**：`背高（实测）× 坐骑倍率 − 胯高（实测比例 0.2080）× 骑士倍率`，
  见 `scripts/world/ModelLibrary.gd` 的 `rider_offset_y`；`tools/party_model_check.gd`
  会断言这个偏移落在合理区间，并断言清单里的每个片段名真能解析到实际片段。

## 2. 尚未入库的同类资产（仅登记，本轮不动）

同批 CC0 资产还有 `bld_keep` / `bld_wall` / `bld_tavern` / `bld_church` / `bld_market` /
`bld_barracks` / `bld_smith` / `bld_tent` / `bld_tower_large` / `bld_tower_small` /
`prop_tree_a` / `prop_tree_b` / `prop_rock_a` / `prop_rock_b`（第③批-3 城镇 / 城堡与
地形装饰用）。部队那批已在 §1b 入库。

## 3. 许可速查

| 许可 | 能否商用 | 是否必须署名 |
|---|---|---|
| CC0 1.0 | 可以 | 不需要 |