# AI NPC Sandbox v2 Design — 连续世界模型 / 自主日程 / 头顶气泡

日期: 2026-06-04(2026-06-04 重大修订: 从"叠视觉层"转向"连续世界模型")

## 目标

v1 首版已完成并合并到 `main`: NPC 接通 OpenRouter `gemini-3.5-flash`, 有 daily-todo 规划(按 `T` 触发) + 每 0.8s 驱动的执行循环, grid-based 世界模型(寻路 / 占用 / 交互 / FencedArea)已通过 APR oracle 验证。

v2 兑现 9 项体验需求 + 1 项新增(拖拽重力感):

1. NPC / 物品不再绑在格子里; 格子只用于放建筑时定位, 平时不显示。
2. 地面做成草地。
3. 人物移动连续平滑。
4. 物品被持有时显示在人物手上。
5. 鼠标滚轮 zoom。
6. 控制方式用 UI 显示。
7. 非建造模式下不再出现选中框。
8. NPC 在早上自动计划一天日程并逐个执行, 不再需要 `T` 手动触发; 选中 NPC 时旁边 UI 显示其日程。
9. NPC 的 intent / 说话用气泡在头顶显示。
10. (新增) 拖拽 NPC / 物品有"重力感" —— 逐渐平滑靠近鼠标, 不再 snap 到格子。

## 核心转向: grid 世界 → 连续世界

> ⚠ 本节**推翻**了本 spec 早期版本的"逻辑层一行不动, 只新增视觉层"铁律。经用户在 spec review 时拍板, v2 是一次**世界模型转向**, 不是表层叠加。

v1 把"格子"当作一切的基础: 位置真相、寻路、占用、交互判定全部以 `Vector2i` 格坐标表达。v2 的根决策是: **NPC / item 的位置真相改为连续 `Vector2`(世界像素坐标); 格子从"位置单位"降级为只服务两件事 —— 建筑摆放定位 + 寻路计算。**

| 维度 | v1(现状) | v2(目标) |
|---|---|---|
| NPC / item 位置真相 | `current_cell: Vector2i` | `position: Vector2`(连续世界像素) |
| 格子角色 | 位置 / 寻路 / 占用 / 交互的共同基础 | **仅建筑摆放定位 + 寻路 BFS 计算** |
| `occupancy` 占用表 | 同格唯一 / 拖拽反查 / 建筑避让 / inventory 一致性 | **移除**(连续坐标无"同格"概念) |
| 移动 | 一拍瞬移到 `planned_path` 末格 | 沿格点航道**逐帧连续行走** |
| 交互判定 | "到达目标格" | **距离阈值**(进半径内即可交互) |
| 拖拽 | snap 到格(`move_entity_to_cell`) | **重力感跟随鼠标**, 松手改连续位置 |
| 选中 | 按 cell 查 occupancy 反查实体 | 对实体 `position` 做**视觉 hit-test** |

### 为什么可行、风险可控(来自代码勘探, 含 `文件:行号` 证据)

1. **寻路天然兼容连续位置。** `GridPathfinder` 只持有 `solid_cells`(`GridPathfinder.gd:7`), `is_walkable`(`:26-29`)只判 `map_bounds` + `solid_cells`, **从不读 NPC / item 占用** —— 其他实体本来就是"透明"的。`solid_cells` 唯一写入来自建筑放置(`BuildingPlacementService.place_fenced_area`)。所以"格点寻路 + 连续行走"= 寻路时把 NPC 连续 `position` 投影到最近格做 BFS(`find_path(start_cell, goal_cell)` 签名不变, `GridPathfinder.gd:32`), 拿到格点串后 NPC 沿其中心连续走。**寻路逻辑几乎不动。**

2. **occupancy 移除是最大改造面, 但下游只有 3 处。** `npc_occupancy` / `item_occupancy`(`WorldEntityRegistry.gd:12-13`)的真正外部消费者: 拖拽选中(`MainGame.gd:159,165,196`)、建筑避让(`BuildingPlacementService.gd:184` 经 `can_place_fenced_area:54-56`)、移动落点校验(`validate_forced_drop:48-59` 经 `move_entity_to_cell`)。改造集中在这三处。

3. **3 个 BLOCKED bug 在新交互模型下自然化解。** v1 的 BLOCKED 根因是"目标格被占 → `validate_forced_drop` 拒绝"(`WorldEntityRegistry.gd:55-58`)+ "目标解析为目标实体当前格"(`TodoExecutor.gd:85-94`)。改成"距离阈值交互"后, inspect/talk 不再要求站到目标格, rest 原地即达标, wander 随机找连续点 —— 根因整体消失。

## 两条贯穿全程的铁律

### 铁律 1 — AI Town 边界(保留)

第 8 项的"自动规划"仍走 `LLM → validate_todos → runtime 采纳` 的 v1 管线。去掉 `T` **只改触发时机**(从按键改成游戏内时钟驱动), 绝不让 NPC 直接写 world state。LLM 永远只提交结构化结果, runtime 校验后才转成 action。

### 铁律 2 — 回归 oracle 是门, 分两类对待(保留, 但回归面比早期版本大)

- 断言"未改行为"的 oracle 必须保持全绿(寻路 walkable、LLM todos 合法性)。
- 因世界模型转向而**本就要变**的 oracle(占用断言、移动 tick 预算、BLOCKED 触发条件), 按 agentic-game-development 流程: **记 pre-state → 改实现 → 复跑 post-state, 把 oracle 更新成新的正确期望**, 不强求字节不变。

逐 oracle 的 pre/post 期望见 [回归 oracle delta](#回归-oracle-delta) 一节。

## 四阶段总览

```
P0 · 连续位置地基   →  P1 · 移动机制       →  P2 · occupancy 移除   →  P3 · 呈现/交互
position 成真相 +      格点寻路+逐帧推进 +     删占用表 + 拖拽         草地 / 视觉hit-test /
world↔cell 换算 +      距离阈值交互 +         重力感 + 建筑避让        滚轮zoom / HUD /
持久视觉节点(B1)      修3个BLOCKED           改遍历 + 选中hit-test    日程侧栏 / 气泡内容 +
                                                                    时钟自动日程
```

阶段按依赖排, P0 是地基。writing-plans 时做成四个 checkpoint, 每个 checkpoint 结束都可独立验证。

---

## P0 · 连续位置地基

### 0.1 `position` 成为位置真相

- `NPCState` / `ItemState` 新增 `position: Vector2`(世界像素)。它是位置的**唯一真相**; `to_dict` / `from_dict` 序列化它。
- `current_cell` **不删, 降级为派生镜像**: 每次 `position` 变更后顺手算 `current_cell = world_to_cell(position)` 同步。所有"读 `current_cell`"的旧代码(寻路投影、建筑判定、存档)继续工作, 只是格子来源从"真相"变成"position 投影出来的"。
- **证据**: 现状 `NPCState.current_cell: Vector2i = Vector2i.ZERO`(`NPCState.gd:11`)、`ItemState.current_cell`(`ItemState.gd:9`)是唯一位置字段。

### 0.2 world ↔ cell 换算

- `Constants` 当前**没有** `cell_size`, 也没有 world↔cell 换算(`_cell_center` 在 `MainGame.gd` 里用局部 `cell_size` 算)。v2 在 `Constants` 引入权威 `CELL_SIZE` + `world_to_cell(pos: Vector2) -> Vector2i` + `cell_to_world_center(cell: Vector2i) -> Vector2`。MainGame 现有的局部换算改为复用它, 避免两套坐标系。

### 0.3 per-NPC / per-item 持久视觉节点(决策 B1, 用户已定)

- 在 `WorldMap`(Node2D)下新增 `EntityVisualLayer`(Node2D), 持有 `npc_id → NPCVisual(Node2D)` 与 `item_id → ItemVisual(Node2D)` 映射。
- `NPCVisual` 子树: 本体(circle/Sprite) + `HeldItemAnchor`(Node2D, 手部挂点) + `SpeechBubble`(气泡容器, 0.5 节)。节点 `position` 镜像 state 的 `position`。
- 视觉层订阅 registry 实体增删(或每帧 diff), 保证节点生死与数据一致: **registry/state 是 truth, 视觉节点是 derived**。
- 从 `MainGame._draw()` 移除 NPC/item 的 `draw_circle`/`draw_rect`(`MainGame.gd:119-126`); 草地与建筑 overlay 仍可留 `_draw()` 或独立节点(P3)。
- **可独立验证点**: P0 完成后 NPC 仍可用旧瞬移逻辑跑(`position` 瞬移到终点 cell 中心), 但画面已由持久节点渲染。移动连续性留给 P1。

### 0.4 气泡容器(第 9 项的视觉载体, 内容在 P3)

- `NPCVisual` 下挂 `SpeechBubble`(Label / RichTextLabel + 圆角背景), 锚在本体上方。本阶段只建容器 + `show_bubble(text)` / 自动淡出 API, **不接内容来源**(内容在 P3.4 接线)。

---

## P1 · 移动机制 — 决策与推进分离

这是 v2 与 v1 差最大的一处。v1 是"一个 tick 内瞬移到 `planned_path` 末格"(`NPCMover.gd:34-45`)。v2 拆成两条节奏:

### 1.1 决策(时钟 / tick 驱动)

- 选定 todo 后, `GridPathfinder` 把 NPC 当前 `position` 投影到格(`world_to_cell`)做 BFS, 得到格点串, 转成**像素航点序列**(`cell_to_world_center`)交给 mover。
- `NPCMover` 不再瞬移; 它保存航点序列, 暴露给逐帧推进逻辑。`move_to_cell` 现有返回值已含完整 `path`(`NPCMover.gd:45`), 复用之。

### 1.2 推进(每帧 `_process(delta)`)

- NPC 的 `position` 朝下一航点按 `npc_speed`(px/s)推进; 到点切下一航点, 走完整条航道。
- 因为 `position` 本身就是真相, **不存在"视觉滞后于逻辑"** —— 逻辑位置与画面位置天生合一(用户在早期决策里选 A2 的初衷"视觉逻辑严格同步", 在连续模型下自动满足)。
- 打断 / 接续: 推进途中来新 todo, 从当前 `position` 平滑连到新航道起点, 不闪现。

### 1.3 交互层 — 距离阈值

- `TodoExecutor._target_cell`(`:76-99`)的目标解析改为返回目标 `position`(或目标格中心):
  - `inspect_item` / `talk_to_npc`: 解析为目标实体 `position`; NPC 走到 `position` 距目标在 `INTERACT_RADIUS`(如 1 格距离)内即达成 —— **站旁边而非站身上**。
  - `visit_place`: 解析为 place 的 door_cell / interior walkable 格中心(保留 v1 能 done 的行为)。
  - `rest`: NPC 当前 `position` 原地即达标(不再要求 `target_cell` 字段, 修掉 `missing_target` BLOCKED)。
  - `wander`: 随机选一个 walkable 且非当前格的 cell 中心走过去(修掉 `_wander_cell` 恒返回 `map_bounds.position` 的死循环, `TodoExecutor.gd:190-194`)。

### 1.4 完成判定 & 3 个 BLOCKED bug

- todo `done` 条件: NPC `position` 距目标 `position` 进入 `INTERACT_RADIUS`。
- 由 1.3 的距离模型, spec 早期列的 3 个 BLOCKED bug(`inspect_item`/`talk_to_npc` 目标被占、`rest` 缺字段、`wander` 死循环)全部化解, 无需再依赖"放开 occupancy"。
- **连锁后果**: 移动不再"1 tick 完成", 执行循环从"发起即完成"变成"发起 → 跨多帧推进 → 到达后判 done"。这正是 `npc_execution_loop_oracle` 要重写的点(见 oracle delta)。

---

## P2 · occupancy 移除

### 2.1 删占用表 + 简化校验

- `WorldEntityRegistry`: 删 `npc_occupancy` / `item_occupancy`(`:12-13`)。
- `validate_forced_drop`(`:48-59`)去掉"格被 NPC/item 占"两条检查(`:55-58`), 只留越界 / 建筑墙(`blocked_cells`)。
- `_rebuild_occupancy`(`:255-263`)+ 同格去重 + `_is_free_cell`(`:230-239`)整套删除。
- `drop_held_item`(`:89-108`)的落点不再靠 `find_nearest_free_cell` 找空格 —— 改为落在持有者 `position` 附近的连续点(若落点在建筑墙内则推到最近 walkable 连续点)。`find_nearest_free_cell` 若无其他消费者则删除, 否则改为只判建筑墙。
- `repair_inventory_links`(`:130-158`)**保留持有关系一致性**(物品在手的"一物一主"去重仍要, 与格子无关), 删去依赖 occupancy 的部分。
- `move_entity_to_cell`(`:62-67`)改为 `set_entity_position(entity_id, pos: Vector2)`: 写连续 `position` + 同步派生 `current_cell`, 不再查占用。

### 2.2 拖拽选中改视觉 hit-test(第 7 项相关)

- v1 选中靠 `get_npc_at_cell` / `get_item_at_cell` 反查(`MainGame.gd:157-173`)。改为**对 `NPCVisual` / `ItemVisual` 的 `position` 做视觉 hit-test**(点击点到实体圆心距离 ≤ 命中半径, 取最近者)。
- "给物品"判定(拖 item 落到某 NPC 上, `MainGame.gd:196-198`)改为: 落点 `position` 命中某 NPC 的 hit 半径 → `give_item_to_npc`。

### 2.3 拖拽重力感(第 10 项, 新增)

- 拖拽中: 每帧把被拖实体 `position` 朝鼠标世界坐标弹性插值(`position += (mouse_world - position) * GRAB_PULL`), 产生"逐渐追上鼠标"的重力感, 不 snap 到格。
- 松手: `position` 停在当前连续位置; 若落在建筑墙内, 平滑推到最近 walkable 连续点。**完全不绑格**(符合"拖动改变位置但不再和格子关联")。

### 2.4 建筑避让改遍历

- `BuildingPlacementService` 判"footprint 上有没有 NPC"从查 `npc_occupancy`(`:184` `get_npcs_occupying_cells`)改为**遍历 NPC `position` 投影格**, 逐个比对 footprint。`can_place_fenced_area`(`:54-56`)的拒绝语义保持。

---

## P3 · 呈现 / 交互

### 3.1 草地(第 2 项)

- 地面改为草地观感(绿色渐变 + 细微噪点), 平时不显示网格线。
- 网格只在放建筑(FencedArea 拖拽)时显示, 用于定位(第 1 项)。`GridSelectionOverlay` 的网格绘制改为仅 `fenced_area_mode` 时可见。

### 3.2 修非建造模式选中框(第 7 项)

- 选中框(drag-rect)只在 `fenced_area_mode` 时绘制。现状 `GridSelectionOverlay._draw()` 与模式无关, 任何左键拖拽都画框(`GridSelectionOverlay.gd:86-93`) —— 这是第 7 项根因。修法: 画框逻辑读 `fenced_area_mode`, 非建造模式不画 drag-rect(选中改用 2.2 的视觉 hit-test, 不依赖框)。

### 3.3 滚轮 zoom + 控制 UI(第 5、6 项)

- **滚轮 zoom**: 鼠标滚轮缩放 `WorldMap` 下的 `Camera2D`(`zoom`), 设上下限, 以鼠标位置为锚点。
- **控制 UI**: HUD 角落折叠提示 —— 角落一行提示, 按 `H` 展开完整按键表。画面默认干净。

### 3.4 日程侧栏 + 气泡内容(第 8、9 项呈现)+ 自动日程时钟

- **轻量游戏内时钟(第 8 项触发器)**: 当前无时间系统(`tick` 只是 `_process` 自增计数器, 不驱动行为)。新增 `GameClock`: 几分钟现实时间 = 一个游戏"天", 一天分若干时段, 至少一个"早上"点。**无昼夜光照**。到"早上"自动触发全体 NPC daily todo 规划; 白天逐个执行; 执行完闲置 / wander, 到次日早上重新规划。暴露 `day` / `time_of_day` 供 HUD 显示。
- **去掉手动 `T`**: 移除 `KEY_T` 作为唯一入口(`MainGame.gd:255`), 改由 `GameClock` 的"早上"事件调用同一 `request_daily_todos_for_all_npcs()`。`T` 可保留为调试手动触发(可选)。铁律 1: 触发器变, 管线不变。
- **日程侧栏**: 选中 NPC 时右侧面板显示 `todo_list`: ✓ 已完成 / ▶ 进行中 / · 待办; 选中 NPC 视觉高亮(金色圈)。数据读 `NPCState.todo_list`(`TodoItem.status`)。
- **气泡内容(零新增 LLM 调用, 需新接线)**: todo 的 `reason` 字段当前无运行时消费者(只存进 `TodoItem.reason`)。开始执行某 todo 时(`TodoExecutor.execute_todo` 入口)把 `reason` 喂 `NPCVisual.show_bubble(reason)`; 事件反馈时把 `NPCFeedbackBuilder` 的输出喂气泡(`NPCFeedbackBuilder.stream_feedback` 走 LLM streaming + 兜底, 气泡接最终输出, 不新增 LLM 调用)。气泡几秒后自动淡出(0.4 容器 API)。

---

## 回归 oracle delta

按铁律 2, 逐 oracle 记 pre-state、定 post-state:

| oracle / 测试 | 文件 | pre-state(现状断言) | v2 受影响点 | post-state(新期望) |
|---|---|---|---|---|
| CORE_BEHAVIORS | `tests/test_core_behaviors.gd` | 大量断言 `npc_occupancy`/`item_occupancy`、移动后占用更新、同格去重、`_rebuild_occupancy` 修复、`npc_occupies_footprint` | occupancy 移除后这些整体失去意义 | **重写**: 保留 inventory 持有一致性(`repair_inventory_links` 的一物一主); 删同格 / 去重断言; 移动断言改"`position` 到达 + 距离达标" |
| NPC_EXECUTION_LOOP | `apr/npc-loop/oracle/npc_execution_loop_oracle.gd:74-83` | "3 次 `tick_npc_execution()` 内移动 + `todo.status==done`"(假设瞬移) | 移动改逐帧推进, 不再 1 tick 完成 | **重写**: 改"驱动 N 帧 / tick 后 `position` 进入目标 `INTERACT_RADIUS` + done", N 按航道长度 |
| NPC_LOOP BLOCKED 用例 | `apr/npc-loop/oracle/npc_loop_oracle.gd:123-147` | 靠"同格被占"触发 BLOCKED | 那条路径不再 BLOCKED | **重写**: 用"真正不可达(建筑围死目标)"触发真 BLOCKED |
| NPC_LOOP planner 断言 | `apr/npc-loop/oracle/npc_loop_oracle.gd:52-82` | 非法 intent/target 丢弃、超限 cap、全非法 fallback 成 wander | intent 集合不变 | **不变** |
| VERIFY_PROJECT | `tools/verify_project.py:86-99` | 断言 `npc_occupancy`/`item_occupancy` 字段 + `validate_forced_drop`/`move_entity_to_cell`/`find_nearest_free_cell` 方法存在 | 字段 / 方法删改后会 FAIL | **更新**: 改校验新结构 `position` / `set_entity_position` / world↔cell 换算 |
| PLAYABLE_UI | `apr/playable-ui/oracle/playable_ui_oracle.gd:42-59` | 场景树含 GridSelectionOverlay / FencedAreaOverlay / FencedAreaEditPanel 等 | 新增 `WorldMap/EntityVisualLayer` + per-NPC 节点; HUD 新增侧栏 / 控制提示 | **更新**: 加入新增节点路径, 保留原有断言 |
| PLACE_REGISTRY_WALKABLE | `apr/place-registry-walkable/oracle/place_registry_walkable_oracle.gd` | `get_random_cell_in_place` / `is_walkable` / `solid_cells` | 寻路 walkable 语义不变 | **不变** |
| LLM_LIVE | `apr/npc-loop/oracle/llm_live_oracle.gd` | 真实联网验 todos 合法(无 key SKIP) | 触发时机改时钟, `request_daily_todos` 管线不变 | **不变**(铁律 1) |

新增的连续移动 / 距离交互 / 拖拽重力感 / 时钟若需可观测断言, 按 agentic-game-development 建对应 oracle / adapter, 记 pre→post。

## v2 不做

1. 不做完整昼夜系统(光照 / 天空 / 夜间行为) —— 时钟是抽象"天"循环, 无画面昼夜。
2. 不做正式美术 pipeline(sprite/tileset/动画 rig) —— 草地 / 气泡 / 持有物仍是 Godot 基础图形 + 文字。
3. 不换寻路算法 —— 仍是 grid BFS(`GridPathfinder`), 只是输入从连续 `position` 投影到格; 不引入 navmesh。
4. 不让 NPC 直接写 world state(铁律 1)。
5. 不为气泡新增专门的 LLM 调用(复用 todo reason + feedback builder 现成输出)。
6. 气泡不做对话系统 / 多轮对白; 只显示单句 intent reason 或单句事件反应。

## 设计结论

v2 是一次**世界模型转向**: 位置真相从 grid `current_cell` 改为连续 `position`, 格子退役成只服务建筑摆放 + 寻路 BFS 计算, occupancy 占用表移除。在此地基上:

1. **连续位置地基(P0)** —— `position` 成真相, world↔cell 换算, per-NPC 持久视觉节点。
2. **移动机制(P1)** —— 决策(tick 寻路)与推进(逐帧连续行走)分离, 距离阈值交互, 3 个 BLOCKED bug 随之化解。
3. **occupancy 移除(P2)** —— 删占用表, 拖拽重力感, 视觉 hit-test 选中, 建筑避让改遍历。
4. **呈现 / 交互(P3)** —— 草地, 滚轮 zoom, HUD, 日程侧栏, 气泡内容, 时钟自动日程。

寻路算法不动, 连续移动天然消除"视觉滞后"; AI Town 边界(铁律 1)与回归 oracle 门(铁律 2)贯穿全程, 因模型转向而本就要变的 oracle 按 pre→post 更新。
