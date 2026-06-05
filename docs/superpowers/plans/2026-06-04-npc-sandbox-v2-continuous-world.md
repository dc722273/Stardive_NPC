# NPC Sandbox v2 — 连续世界模型 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 NPC/物品的位置真相从 grid `current_cell` 转为连续 `position: Vector2`,格子退役为只服务建筑摆放 + 寻路 BFS;在此地基上做连续平滑移动、距离阈值交互、occupancy 移除、拖拽重力感、草地/滚轮/HUD/日程侧栏/头顶气泡、时钟自动日程。

**Architecture:** 四阶段 P0→P3 顺序推进。P0 立连续位置地基与持久视觉节点(NPC 仍可瞬移,但已由持久节点渲染);P1 把移动拆成"决策(tick 寻路)+ 推进(逐帧连续行走)"并以距离阈值判交互、化解 3 个 BLOCKED bug;P2 移除 occupancy 占用表、改拖拽为重力感跟随、选中改视觉 hit-test、建筑避让改遍历;P3 做草地/滚轮 zoom/HUD/日程侧栏/气泡内容 + 时钟自动日程。寻路算法(`GridPathfinder` grid BFS)不换,只把连续 `position` 投影到格做输入。

**Tech Stack:** Godot 4.6.3 (GDScript, gl_compatibility);自研 oracle harness(`apr/`)+ SceneTree 单测聚合(`tests/run_tests.gd`)+ 静态校验(`tools/verify_project.py`)。

**设计依据:** `docs/superpowers/specs/2026-06-04-npc-sandbox-v2-design.md`

---

## 关键约定(所有 task 通用)

**运行测试的命令(Windows bash 环境,用 PowerShell 包装器):**

- 全部 GDScript 单测:`powershell.exe -File tools/godot/run-tests.ps1`
  期望末行:`GODOT_TESTS: PASS`(退出码 0)。**注意**:Godot 输出里任何 `SCRIPT ERROR` / `ERROR:`(含 `push_error` 文本)都会让退出码变 1 —— 写"期望失败"的测试时,断言失败要走 oracle 的 `failures` 累加,不要用 `push_error` 制造预期失败。
- 单个 SceneTree oracle:`powershell.exe -File tools/godot/godot.ps1 --headless --script <path-to-oracle.gd>`
  期望末行是该 oracle 的 `*_ORACLE: PASS`。
- npc-loop oracle(带 runner):`python apr/npc-loop/oracle/run_npc_loop_oracle.py`
- place-registry oracle:`python apr/place-registry-walkable/oracle/run_place_registry_walkable_oracle.py`
- playable-ui oracle:`python apr/playable-ui/oracle/run_playable_ui_oracle.py`
- 静态结构校验:`python tools/verify_project.py` → 期望 `VERIFY_PROJECT: PASS`

**Godot 可执行文件:** `tools/godot/Godot_v4.6.3-stable_win64_console.exe`(`godot.ps1` 自动定位并注入 `--path`)。

**坐标系约定(本计划引入):** `Constants.CELL_SIZE = 32`(与现 `MainGame.cell_size` 默认一致)。`world_to_cell(pos)` = `Vector2i(floor(pos.x / CELL_SIZE), floor(pos.y / CELL_SIZE))`;`cell_to_world_center(cell)` = `Vector2(cell.x * CELL_SIZE + CELL_SIZE*0.5, cell.y * CELL_SIZE + CELL_SIZE*0.5)`。

**提交纪律:** 每个 task 末尾 commit。当前在 `main` 分支;若用户选择 worktree 隔离,执行前会先开分支。

---

## P0 · 连续位置地基

P0 目标:`position: Vector2` 成为 NPC/item 位置真相,`current_cell` 降级为派生镜像;`Constants` 提供 world↔cell 换算;引入 per-NPC/item 持久视觉节点(`EntityVisualLayer`)。**P0 结束时 NPC 仍用旧瞬移逻辑移动(position 瞬移到终点 cell 中心),但画面已由持久节点渲染** —— 移动连续性留给 P1,保证每步独立可验证。

### Task 0.1: Constants 增加 CELL_SIZE 与 world↔cell 换算

**Files:**
- Modify: `scripts/core/Constants.gd`
- Test: `tests/test_core_behaviors.gd`(在 `run()` 注册 + 新增测试函数)

- [ ] **Step 1: 写失败测试**

在 `tests/test_core_behaviors.gd` 的 `run()` 方法里(现有 `_test_constants()` 调用之后)加一行调用,并新增测试函数:

```gdscript
# 在 run() 中,_test_constants() 之后加:
	_test_world_cell_conversions(failures)
```

```gdscript
func _test_world_cell_conversions(failures: Array) -> void:
	# CELL_SIZE 是连续世界的权威格尺寸。
	_expect_equal(failures, ConstantsScript.CELL_SIZE, 32, "CELL_SIZE is 32")
	# world_to_cell: 向下取整到所属格。
	_expect_equal(failures, ConstantsScript.world_to_cell(Vector2(0, 0)), Vector2i(0, 0), "world_to_cell origin")
	_expect_equal(failures, ConstantsScript.world_to_cell(Vector2(40, 72)), Vector2i(1, 2), "world_to_cell mid-cell")
	_expect_equal(failures, ConstantsScript.world_to_cell(Vector2(64, 64)), Vector2i(2, 2), "world_to_cell on boundary")
	# cell_to_world_center: 格中心像素。
	_expect_equal(failures, ConstantsScript.cell_to_world_center(Vector2i(0, 0)), Vector2(16, 16), "cell center origin")
	_expect_equal(failures, ConstantsScript.cell_to_world_center(Vector2i(2, 1)), Vector2(80, 48), "cell center 2,1")
```

> 若 `tests/test_core_behaviors.gd` 没有 `_expect_equal` helper,改用文件内已有的断言 helper(查看 `run()` 上下文里现有的 `_test_constants` 怎么断言,沿用同名 helper)。

- [ ] **Step 2: 跑测试确认失败**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: FAIL —— `CELL_SIZE`/`world_to_cell`/`cell_to_world_center` 不存在(报 `Invalid call` 或 `GODOT_TESTS: FAIL`)。

- [ ] **Step 3: 实现 Constants 换算**

在 `scripts/core/Constants.gd` 的 `const INVALID_CELL` 之后加:

```gdscript
const CELL_SIZE := 32


static func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_SIZE)), int(floor(pos.y / CELL_SIZE)))


static func cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL_SIZE + CELL_SIZE * 0.5, cell.y * CELL_SIZE + CELL_SIZE * 0.5)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`

- [ ] **Step 5: 确认 verify_project 仍绿**

Run: `python tools/verify_project.py`
Expected: `VERIFY_PROJECT: PASS`(`verify_project.py:311-319` 只要求 `class_name Constants`/`INVALID_CELL`/`Vector2i(-1, -1)`,新增常量不破坏)。

- [ ] **Step 6: Commit**

```bash
git add scripts/core/Constants.gd tests/test_core_behaviors.gd
git commit -m "feat(p0): add CELL_SIZE + world<->cell conversions to Constants"
```

---

### Task 0.2: NPCState / ItemState 增加 position 字段(真相 + 派生 current_cell)

**Files:**
- Modify: `scripts/state/NPCState.gd`
- Modify: `scripts/state/ItemState.gd`
- Modify: `tools/verify_project.py:14-22, 26-32`(字段期望表加 `position`)
- Test: `tests/test_core_behaviors.gd`

设计:`position: Vector2` 是真相;`current_cell` 保留,作为 `world_to_cell(position)` 的派生镜像。`from_dict`:若 data 有 `position` 用之并派生 `current_cell`;否则(v1 旧存档)从 `current_cell` 用 `cell_to_world_center` 反推 `position`(向后兼容)。`to_dict` 两者都写。

- [ ] **Step 1: 写失败测试**

在 `run()` 注册 `_test_position_is_source_of_truth(failures)`,新增:

```gdscript
func _test_position_is_source_of_truth(failures: Array) -> void:
	# 新存档带 position：position 是真相,current_cell 派生。
	var npc = NPCStateScript.from_dict({
		"id": "npc_a", "display_name": "A", "personality": "x",
		"position": {"x": 80.0, "y": 48.0},
	})
	_expect_equal(failures, npc.position, Vector2(80, 48), "npc position from dict")
	_expect_equal(failures, npc.current_cell, Vector2i(2, 1), "npc current_cell derived from position")
	# 往返保留 position。
	var round = NPCStateScript.from_dict(npc.to_dict())
	_expect_equal(failures, round.position, Vector2(80, 48), "npc position round-trips")
	# 旧存档只有 current_cell：position 从格中心反推。
	var legacy = NPCStateScript.from_dict({"id": "npc_b", "current_cell": {"x": 4, "y": 4}})
	_expect_equal(failures, legacy.position, Vector2(144, 144), "legacy npc position from cell center")
	# Item 同理。
	var item = ItemStateScript.from_dict({"id": "it_a", "position": {"x": 16.0, "y": 16.0}})
	_expect_equal(failures, item.position, Vector2(16, 16), "item position from dict")
	_expect_equal(failures, item.current_cell, Vector2i(0, 0), "item current_cell derived")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: FAIL —— `position` 字段不存在。

- [ ] **Step 3: 实现 NPCState.position**

`scripts/state/NPCState.gd`:在 `var current_cell: Vector2i = Vector2i.ZERO`(`:11`)后加字段,并改 `from_dict`/`to_dict`。

加字段(`:11` 之后):
```gdscript
var position: Vector2 = Vector2.ZERO
```

改 `from_dict`(替换 `:22` 那行 `state.current_cell = ...`):
```gdscript
	if data.has("position"):
		state.position = _vec2_from(data["position"])
		state.current_cell = ConstantsScript.world_to_cell(state.position)
	else:
		state.current_cell = ConstantsScript.cell_from_dict(data.get("current_cell", Vector2i.ZERO), Vector2i.ZERO)
		state.position = ConstantsScript.cell_to_world_center(state.current_cell)
```

改 `to_dict`(在返回字典里 `current_cell` 那项旁边加 `position`):
```gdscript
		"position": {"x": position.x, "y": position.y},
```

在文件末尾加 helper:
```gdscript
static func _vec2_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO
```

- [ ] **Step 4: 实现 ItemState.position**

`scripts/state/ItemState.gd`:在 `var current_cell: Vector2i = Vector2i.ZERO`(`:9`)后加 `var position: Vector2 = Vector2.ZERO`。

改 `from_dict`(`:19-22` 的 if/else 块):持有态保持 `current_cell = INVALID_CELL`、`position = Vector2.ZERO`;否则同 NPCState 逻辑:
```gdscript
		if state.held_by_npc_id != &"":
			state.current_cell = ConstantsScript.INVALID_CELL
			state.position = Vector2.ZERO
		elif data.has("position"):
			state.position = _vec2_from(data["position"])
			state.current_cell = ConstantsScript.world_to_cell(state.position)
		else:
			state.current_cell = ConstantsScript.cell_from_dict(data.get("current_cell", Vector2.ZERO), Vector2i.ZERO)
			state.position = ConstantsScript.cell_to_world_center(state.current_cell)
```

`to_dict` 加 `"position": {"x": position.x, "y": position.y},`,并加同样的 `_vec2_from` helper。

- [ ] **Step 5: 更新 verify_project 字段期望**

`tools/verify_project.py`:在 `STATE_EXPECTATIONS` 的 `NPCState.gd` fields(`:14-22`)加 `"position",`;`ItemState.gd` fields(`:26-32`)加 `"position",`。

- [ ] **Step 6: 跑测试确认通过**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`

- [ ] **Step 7: 跑 verify_project 确认通过**

Run: `python tools/verify_project.py`
Expected: `VERIFY_PROJECT: PASS`

- [ ] **Step 8: Commit**

```bash
git add scripts/state/NPCState.gd scripts/state/ItemState.gd tools/verify_project.py tests/test_core_behaviors.gd
git commit -m "feat(p0): position becomes source of truth, current_cell derived"
```

---

### Task 0.3: EntityVisualLayer + NPCVisual/ItemVisual 持久节点

**Files:**
- Create: `scripts/ui/EntityVisualLayer.gd`
- Create: `scripts/ui/NPCVisual.gd`
- Create: `scripts/ui/ItemVisual.gd`
- Test: `apr/playable-ui/oracle/playable_ui_oracle.gd`(加节点断言)+ 新建 `apr/entity-visual/oracle/entity_visual_oracle.gd`

设计:`EntityVisualLayer`(Node2D)挂在 `WorldMap` 下,持有 `npc_visuals: Dictionary`(npc_id→NPCVisual)、`item_visuals: Dictionary`。方法 `sync_from_registry(entity_registry)`:对 registry 里每个 NPC/item 确保有对应 visual 节点(没有则建、删了则移除),并把节点 `position` 设为 state 的 `position`。`NPCVisual` 子树:本体 circle(`_draw` 画)+ `HeldItemAnchor`(Node2D)+ `SpeechBubble`(Label,P0.4 建容器)。

- [ ] **Step 1: 写失败 oracle**

Create `apr/entity-visual/oracle/entity_visual_oracle.gd`:

```gdscript
extends SceneTree

const PASS_MARKER := "ENTITY_VISUAL_ORACLE: PASS"
const FAIL_MARKER := "ENTITY_VISUAL_ORACLE: FAIL"

const EntityVisualLayerScript := preload("res://scripts/ui/EntityVisualLayer.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 24, 16))
	registry.add_npc(NPCStateScript.from_dict({"id": "npc_a", "position": {"x": 80.0, "y": 48.0}}))
	registry.add_item(ItemStateScript.from_dict({"id": "it_a", "position": {"x": 16.0, "y": 16.0}}))

	var layer = EntityVisualLayerScript.new()
	get_root().add_child(layer)
	layer.sync_from_registry(registry)

	# 每个 NPC/item 有对应持久节点。
	_assert_true(layer.npc_visuals.has(StringName("npc_a")), "npc visual created")
	_assert_true(layer.item_visuals.has(StringName("it_a")), "item visual created")
	# 节点 position 镜像 state position。
	var nv = layer.npc_visuals[StringName("npc_a")]
	_assert_true(nv.position == Vector2(80, 48), "npc visual mirrors position, got %s" % str(nv.position))
	# NPCVisual 有 HeldItemAnchor 与 SpeechBubble 子节点。
	_assert_true(nv.get_node_or_null("HeldItemAnchor") != null, "has HeldItemAnchor")
	_assert_true(nv.get_node_or_null("SpeechBubble") != null, "has SpeechBubble")

	# registry 删除实体后,sync 移除其节点。
	registry.npcs.erase(StringName("npc_a"))
	layer.sync_from_registry(registry)
	_assert_true(not layer.npc_visuals.has(StringName("npc_a")), "npc visual removed after registry delete")


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/entity-visual/oracle/entity_visual_oracle.gd`
Expected: FAIL —— `EntityVisualLayer.gd` 不存在(加载错误)。

- [ ] **Step 3: 实现 NPCVisual / ItemVisual / EntityVisualLayer**

Create `scripts/ui/NPCVisual.gd`:
```gdscript
extends Node2D
class_name NPCVisual

const ConstantsScript := preload("res://scripts/core/Constants.gd")

var npc_id: StringName = &""
var selected: bool = false


func _ready() -> void:
	if get_node_or_null("HeldItemAnchor") == null:
		var anchor := Node2D.new()
		anchor.name = "HeldItemAnchor"
		anchor.position = Vector2(ConstantsScript.CELL_SIZE * 0.3, 0)
		add_child(anchor)
	if get_node_or_null("SpeechBubble") == null:
		var bubble := Label.new()
		bubble.name = "SpeechBubble"
		bubble.position = Vector2(-40, -ConstantsScript.CELL_SIZE)
		bubble.visible = false
		add_child(bubble)


func _draw() -> void:
	var color := Color(0.34, 0.64, 0.95, 1.0)
	draw_circle(Vector2.ZERO, ConstantsScript.CELL_SIZE * 0.28, color)
	if selected:
		draw_arc(Vector2.ZERO, ConstantsScript.CELL_SIZE * 0.34, 0, TAU, 24, Color(1.0, 0.84, 0.0, 1.0), 2.0)
```

Create `scripts/ui/ItemVisual.gd`:
```gdscript
extends Node2D
class_name ItemVisual

const ConstantsScript := preload("res://scripts/core/Constants.gd")

var item_id: StringName = &""


func _draw() -> void:
	draw_rect(Rect2(Vector2(-8, -8), Vector2(16, 16)), Color(0.92, 0.73, 0.24, 1.0), true)
```

Create `scripts/ui/EntityVisualLayer.gd`:
```gdscript
extends Node2D
class_name EntityVisualLayer

const NPCVisualScript := preload("res://scripts/ui/NPCVisual.gd")
const ItemVisualScript := preload("res://scripts/ui/ItemVisual.gd")

var npc_visuals: Dictionary = {}   # npc_id -> NPCVisual
var item_visuals: Dictionary = {}  # item_id -> ItemVisual


func sync_from_registry(entity_registry) -> void:
	if entity_registry == null:
		return
	_sync_npcs(entity_registry)
	_sync_items(entity_registry)


func _sync_npcs(entity_registry) -> void:
	# 建/更新存在的。
	for npc_id in entity_registry.npcs.keys():
		var npc = entity_registry.npcs[npc_id]
		var visual = npc_visuals.get(npc_id)
		if visual == null:
			visual = NPCVisualScript.new()
			visual.npc_id = npc_id
			add_child(visual)
			npc_visuals[npc_id] = visual
		visual.position = npc.position
	# 删除 registry 里已没有的。
	for npc_id in npc_visuals.keys().duplicate():
		if not entity_registry.npcs.has(npc_id):
			npc_visuals[npc_id].queue_free()
			npc_visuals.erase(npc_id)


func _sync_items(entity_registry) -> void:
	for item_id in entity_registry.items.keys():
		var item = entity_registry.items[item_id]
		var visual = item_visuals.get(item_id)
		if visual == null:
			visual = ItemVisualScript.new()
			visual.item_id = item_id
			add_child(visual)
			item_visuals[item_id] = visual
		visual.position = item.position
	for item_id in item_visuals.keys().duplicate():
		if not entity_registry.items.has(item_id):
			item_visuals[item_id].queue_free()
			item_visuals.erase(item_id)
```

> 注意 `_ready` 里建子节点:oracle 里 `EntityVisualLayerScript.new()` 后 `add_child` 触发 NPCVisual 的 `_ready`。若 NPCVisual 节点是用 `.new()` 直接建、未进树,`_ready` 不触发 —— 故 `_sync_npcs` 里 `add_child(visual)` 必须在设 `position` 之前,确保进树后 `_ready` 建好 HeldItemAnchor/SpeechBubble。当前代码顺序正确(先 add_child 再设 position)。

- [ ] **Step 4: 跑 oracle 确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/entity-visual/oracle/entity_visual_oracle.gd`
Expected: `ENTITY_VISUAL_ORACLE: PASS`

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/EntityVisualLayer.gd scripts/ui/NPCVisual.gd scripts/ui/ItemVisual.gd apr/entity-visual/oracle/entity_visual_oracle.gd
git commit -m "feat(p0): persistent EntityVisualLayer + NPCVisual/ItemVisual nodes"
```

---

### Task 0.4: MainGame 接入 EntityVisualLayer,移除 _draw 实体绘制

**Files:**
- Modify: `scenes/main.tscn`(WorldMap 下加 EntityVisualLayer 节点)
- Modify: `scripts/MainGame.gd:48-56`(成员)、`:110-126`(_draw)、`:407-434`(_resolve_scene_nodes)、`:85-93`(_process 每帧 sync)
- Modify: `apr/playable-ui/oracle/playable_ui_oracle.gd:46-47`(加节点断言)
- Modify: `apr/playable-ui/oracle/run_playable_ui_oracle.py`(若静态断言要求 _draw 画实体,放宽)

- [ ] **Step 1: 更新 playable-ui oracle 加节点断言(失败测试)**

`apr/playable-ui/oracle/playable_ui_oracle.gd`:在 `:46-47` 校验 `WorldMap/GridSelectionOverlay`、`WorldMap/FencedAreaOverlay` 处,加一条:
```gdscript
	_assert_has_node(scene_root, "WorldMap/EntityVisualLayer", failures)
```
(沿用文件内已有的 `_assert_has_node` helper 命名;若名字不同,照现有断言风格写。)

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `python apr/playable-ui/oracle/run_playable_ui_oracle.py`
Expected: FAIL(场景树缺 `WorldMap/EntityVisualLayer`)。

- [ ] **Step 3: 场景树加 EntityVisualLayer 节点**

`scenes/main.tscn`:在 ext_resource 区加脚本引用,在 `WorldMap` 下 `FencedAreaOverlay` 后加节点。

加 ext_resource(在 `:6` 后):
```
[ext_resource type="Script" path="res://scripts/ui/EntityVisualLayer.gd" id="5_entity_visual"]
```
加节点(在 `:20` FencedAreaOverlay 节点块后):
```
[node name="EntityVisualLayer" type="Node2D" parent="WorldMap"]
script = ExtResource("5_entity_visual")
```

- [ ] **Step 4: MainGame 持有并每帧 sync,_draw 移除实体绘制**

`scripts/MainGame.gd`:

加成员(`:53` `grid_selection_overlay` 附近):
```gdscript
var entity_visual_layer
```

`_resolve_scene_nodes`(`:407` 起)末尾(camera 解析后)加:
```gdscript
	entity_visual_layer = world_map.get_node_or_null("EntityVisualLayer")
	if entity_visual_layer == null:
		entity_visual_layer = preload("res://scripts/ui/EntityVisualLayer.gd").new()
		entity_visual_layer.name = "EntityVisualLayer"
		world_map.add_child(entity_visual_layer)
```

`_process`(`:85`)在 `queue_redraw()` 前加每帧 sync:
```gdscript
	if entity_visual_layer != null:
		entity_visual_layer.sync_from_registry(entity_registry)
```

`_draw`(`:110-126`):**删除** NPC `draw_circle` 循环(`:119-121`)和 item `draw_rect` 循环(`:122-126`),只保留网格线绘制(`:111-118`)。

> 注意:此时 NPC position 还没被移动逻辑更新(P1 做)。为让 P0 画面正确,在 `_seed_sample_npc_item_data` 不需改(position 已由 from_dict 从 current_cell 派生)。但旧瞬移移动只改 `current_cell` 不改 `position` —— 见 Step 5 临时桥接。

- [ ] **Step 5: 临时桥接 — 旧瞬移移动后同步 position**

P1 之前,移动仍走 `move_entity_to_cell`(只改 `current_cell`)。为让视觉节点跟上,在 `WorldEntityRegistry._move_npc_to_cell`(`:204-213`)和 `_move_item_to_cell`(`:216-227`)设 `current_cell` 后,补设 `position`:

`_move_npc_to_cell` 在 `npc.current_cell = target_cell`(`:211`)后加:
```gdscript
	npc.position = ConstantsScript.cell_to_world_center(target_cell)
```
`_move_item_to_cell` 在 `item.current_cell = target_cell`(`:225`)后加:
```gdscript
	item.position = ConstantsScript.cell_to_world_center(target_cell)
```
同理 `give_item_to_npc`(`:83` `item.current_cell = INVALID_CELL` 后)设 `item.position = Vector2.ZERO`;`drop_held_item`(`:103` 后)设 `item.position = ConstantsScript.cell_to_world_center(target_cell)`。

> 这是 P0→P1 的临时桥接:让"position 随瞬移更新"保证 P0 画面正确。P1 会用连续推进取代瞬移,届时 position 由推进逻辑写,这些桥接行变成冗余(P1 Task 会清理)。

- [ ] **Step 6: 跑 playable-ui oracle 确认通过**

Run: `python apr/playable-ui/oracle/run_playable_ui_oracle.py`
Expected: PASS。若 runner 的静态文本断言(`run_playable_ui_oracle.py:81-240`)要求 `_draw` 里出现 `draw_circle`/`draw_rect`,把那条断言改为校验 `EntityVisualLayer`/`sync_from_registry` 字样(即实体绘制已迁出 _draw)。

- [ ] **Step 7: 跑全部单测 + verify_project 确认未回归**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`(`_move_npc_to_cell` 等的桥接行不破坏现有断言:测试只查 `current_cell`/`occupancy`,新增 position 写入无副作用)。

Run: `python tools/verify_project.py`
Expected: `VERIFY_PROJECT: PASS`

- [ ] **Step 8: Commit**

```bash
git add scenes/main.tscn scripts/MainGame.gd scripts/world/WorldEntityRegistry.gd apr/playable-ui/oracle/
git commit -m "feat(p0): wire EntityVisualLayer into MainGame, move entity rendering out of _draw"
```

---

### Task 0.5: SpeechBubble 容器 API(show_bubble + 自动淡出)

**Files:**
- Modify: `scripts/ui/NPCVisual.gd`
- Test: `apr/entity-visual/oracle/entity_visual_oracle.gd`(加气泡 API 断言)

设计:`NPCVisual.show_bubble(text: String)` 设 SpeechBubble 文本 + visible=true + 重置淡出计时;`_process(delta)` 倒计时,到点 visible=false。本阶段只建容器与 API,**不接内容来源**(P3.4 接)。

- [ ] **Step 1: 写失败断言**

在 `entity_visual_oracle.gd` 的 `_run()` 末尾加:
```gdscript
	# 气泡 API:show_bubble 后可见且带文本。
	nv = layer.npc_visuals.get(StringName("it_a"))  # 用任意存在的 NPCVisual
	# 注:用真正存在的 npc。重新建一个 registry+layer 测气泡更干净:
	var reg2 = WorldEntityRegistryScript.new()
	reg2.set_map_bounds(Rect2i(0, 0, 24, 16))
	reg2.add_npc(NPCStateScript.from_dict({"id": "npc_x", "position": {"x": 16.0, "y": 16.0}}))
	var layer2 = EntityVisualLayerScript.new()
	get_root().add_child(layer2)
	layer2.sync_from_registry(reg2)
	var nvx = layer2.npc_visuals[StringName("npc_x")]
	nvx.show_bubble("去看看可乐")
	var bubble = nvx.get_node("SpeechBubble")
	_assert_true(bubble.visible, "bubble visible after show_bubble")
	_assert_true(bubble.text == "去看看可乐", "bubble text set")
```

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/entity-visual/oracle/entity_visual_oracle.gd`
Expected: FAIL —— `show_bubble` 方法不存在。

- [ ] **Step 3: 实现 show_bubble + 淡出**

`scripts/ui/NPCVisual.gd` 加成员与方法:
```gdscript
var _bubble_timer: float = 0.0
const BUBBLE_DURATION := 4.0


func show_bubble(text: String) -> void:
	var bubble := get_node_or_null("SpeechBubble") as Label
	if bubble == null:
		return
	bubble.text = text
	bubble.visible = true
	_bubble_timer = BUBBLE_DURATION


func _process(delta: float) -> void:
	if _bubble_timer > 0.0:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			var bubble := get_node_or_null("SpeechBubble") as Label
			if bubble != null:
				bubble.visible = false
```

- [ ] **Step 4: 跑 oracle 确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/entity-visual/oracle/entity_visual_oracle.gd`
Expected: `ENTITY_VISUAL_ORACLE: PASS`

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/NPCVisual.gd apr/entity-visual/oracle/entity_visual_oracle.gd
git commit -m "feat(p0): SpeechBubble container API (show_bubble + auto fade)"
```

---

**P0 完成验收:** `position` 是真相、`current_cell` 派生;`Constants` 有 world↔cell 换算;持久视觉节点渲染 NPC/item;气泡容器就绪。NPC 仍瞬移(position 随之跳),画面已由节点驱动。全部 oracle + 单测 + verify_project 绿。

---

## P1 · 移动机制 — 决策与推进分离

P1 目标:把移动从"一拍瞬移到末格"拆成 **决策(tick 寻路,产出像素航点序列)** + **推进(每帧朝下一航点按速度移动 `position`)**。交互改 **距离阈值**(进 `INTERACT_RADIUS` 即达成),修掉 3 个 BLOCKED bug。`current_cell` 在每次 position 推进后由 `world_to_cell` 同步,寻路投影继续用它。

**核心数据结构:** NPCMover 持有 `waypoints: Array[Vector2]`(像素航点队列)+ `arrival_target: Vector2`(本段终点)+ `interact_target: Vector2`(交互判定锚点,通常 = 目标实体 position)。新方法:
- `begin_move(npc, target_world_pos, interact_target, todo)`:寻路(投影到格 BFS)→ 填 `waypoints`。
- `advance(npc, delta) -> Dictionary`:朝下一航点推进 position,返回 `{arrived: bool, interacting: bool}`。
- `is_idle() -> bool`:waypoints 空。

**常量:** `Constants.NPC_SPEED := 96.0`(px/s,约 3 格/秒)、`Constants.INTERACT_RADIUS := 40.0`(px,约 1.25 格)。

### Task 1.1: Constants 增加 NPC_SPEED 与 INTERACT_RADIUS

**Files:**
- Modify: `scripts/core/Constants.gd`
- Test: `tests/test_core_behaviors.gd`

- [ ] **Step 1: 写失败测试**

`run()` 注册 `_test_movement_constants(failures)`:
```gdscript
func _test_movement_constants(failures: Array) -> void:
	_expect_equal(failures, ConstantsScript.NPC_SPEED, 96.0, "NPC_SPEED is 96 px/s")
	_expect_equal(failures, ConstantsScript.INTERACT_RADIUS, 40.0, "INTERACT_RADIUS is 40 px")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: FAIL —— 常量不存在。

- [ ] **Step 3: 实现常量**

`scripts/core/Constants.gd` 在 `const CELL_SIZE := 32` 后加:
```gdscript
const NPC_SPEED := 96.0
const INTERACT_RADIUS := 40.0
```

- [ ] **Step 4: 跑测试确认通过**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`

- [ ] **Step 5: Commit**

```bash
git add scripts/core/Constants.gd tests/test_core_behaviors.gd
git commit -m "feat(p1): add NPC_SPEED + INTERACT_RADIUS constants"
```

---

### Task 1.2: NPCMover 增加连续推进 API(begin_move / advance / is_idle)

**Files:**
- Modify: `scripts/npc/NPCMover.gd`
- Test: 新建 `apr/continuous-move/oracle/continuous_move_oracle.gd`

设计:`begin_move` 把连续起点投影到格、目标投影到格做 BFS,得到格点串,转成像素航点(`cell_to_world_center`),去掉与当前 position 几乎重合的首航点。`advance` 每帧朝 `waypoints[0]` 移动 `NPC_SPEED*delta`,到点(距离 < 步长)就 pop;全部 pop 完则到达;同时检测 `position` 距 `interact_target` 是否进 `INTERACT_RADIUS`(进了就 `interacting=true`,可提前停)。

- [ ] **Step 1: 写失败 oracle**

Create `apr/continuous-move/oracle/continuous_move_oracle.gd`:
```gdscript
extends SceneTree

const PASS_MARKER := "CONTINUOUS_MOVE_ORACLE: PASS"
const FAIL_MARKER := "CONTINUOUS_MOVE_ORACLE: FAIL"

const NPCMoverScript := preload("res://scripts/npc/NPCMover.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ConstantsScript := preload("res://scripts/core/Constants.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 24, 16))
	var mover = NPCMoverScript.new()
	mover.configure(null, null, pathfinder, null)

	# NPC 从 (1,1) 格中心出发,目标 (5,1) 格中心。
	var npc = NPCStateScript.from_dict({"id": "npc_a", "position": {"x": 48.0, "y": 48.0}})
	var goal := ConstantsScript.cell_to_world_center(Vector2i(5, 1))  # (176, 48)
	mover.begin_move(npc, goal, goal, null)

	_assert_true(not mover.is_idle(), "mover busy after begin_move")
	var start_pos := npc.position

	# 推进若干帧(模拟 1/30s 步长),应连续逼近目标且不瞬移。
	var arrived := false
	var steps := 0
	while steps < 600 and not arrived:
		var r: Dictionary = mover.advance(npc, 1.0 / 30.0)
		arrived = bool(r.get("arrived", false)) or bool(r.get("interacting", false))
		steps += 1

	_assert_true(arrived, "npc arrives within step budget, steps=%d" % steps)
	# 连续:不是一帧到位(至少几十帧)。
	_assert_true(steps > 10, "movement is continuous (steps=%d > 10)" % steps)
	# 最终 position 进入目标 INTERACT_RADIUS。
	_assert_true(npc.position.distance_to(goal) <= ConstantsScript.INTERACT_RADIUS, "ends within interact radius, dist=%.1f" % npc.position.distance_to(goal))
	# current_cell 跟随 position 更新(派生镜像)。
	_assert_true(npc.current_cell == ConstantsScript.world_to_cell(npc.position), "current_cell mirrors position")
	# 起点确实移动了。
	_assert_true(npc.position != start_pos, "position changed from start")


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/continuous-move/oracle/continuous_move_oracle.gd`
Expected: FAIL —— `begin_move`/`advance`/`is_idle` 不存在。

- [ ] **Step 3: 实现 NPCMover 连续推进**

`scripts/npc/NPCMover.gd` 加成员(`:13` `planned_path` 后):
```gdscript
var waypoints: Array = []          # Array[Vector2] 像素航点
var interact_target: Vector2 = Vector2.ZERO
```

加方法(文件末尾):
```gdscript
func begin_move(p_npc, target_world_pos: Vector2, p_interact_target: Vector2, p_todo = null) -> void:
	npc = p_npc
	current_todo = p_todo
	interact_target = p_interact_target
	waypoints = []
	if pathfinder == null or npc == null:
		return
	var start_cell: Vector2i = ConstantsScript.world_to_cell(npc.position)
	var goal_cell: Vector2i = ConstantsScript.world_to_cell(target_world_pos)
	target_cell = goal_cell
	planned_path = pathfinder.find_path(start_cell, goal_cell)
	for cell in planned_path:
		var wp: Vector2 = ConstantsScript.cell_to_world_center(cell)
		# 跳过与当前 position 几乎重合的首航点。
		if wp.distance_to(npc.position) < 1.0:
			continue
		waypoints.append(wp)
	# 末航点用精确目标 world pos(交互锚点),让 NPC 停在目标附近而非格中心。
	if not waypoints.is_empty():
		waypoints[waypoints.size() - 1] = target_world_pos


func advance(p_npc, delta: float) -> Dictionary:
	npc = p_npc
	if npc == null:
		return {"arrived": true, "interacting": false}
	# 已在交互半径内：提前停,视为到达。
	if npc.position.distance_to(interact_target) <= ConstantsScript.INTERACT_RADIUS:
		waypoints = []
		npc.current_cell = ConstantsScript.world_to_cell(npc.position)
		return {"arrived": true, "interacting": true}
	if waypoints.is_empty():
		npc.current_cell = ConstantsScript.world_to_cell(npc.position)
		return {"arrived": true, "interacting": false}
	var step: float = ConstantsScript.NPC_SPEED * delta
	var next_wp: Vector2 = waypoints[0]
	var to_wp: Vector2 = next_wp - npc.position
	if to_wp.length() <= step:
		npc.position = next_wp
		waypoints.pop_front()
	else:
		npc.position += to_wp.normalized() * step
	npc.current_cell = ConstantsScript.world_to_cell(npc.position)
	var arrived: bool = waypoints.is_empty()
	var interacting: bool = npc.position.distance_to(interact_target) <= ConstantsScript.INTERACT_RADIUS
	return {"arrived": arrived, "interacting": interacting}


func is_idle() -> bool:
	return waypoints.is_empty()
```

- [ ] **Step 4: 跑 oracle 确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/continuous-move/oracle/continuous_move_oracle.gd`
Expected: `CONTINUOUS_MOVE_ORACLE: PASS`

- [ ] **Step 5: 跑全部单测确认未回归**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`(`begin_move`/`advance` 是新增方法,不动旧 `move_to_cell`,现有 mover 测试不受影响)。

- [ ] **Step 6: Commit**

```bash
git add scripts/npc/NPCMover.gd apr/continuous-move/oracle/continuous_move_oracle.gd
git commit -m "feat(p1): NPCMover continuous advance API (begin_move/advance/is_idle)"
```

---

### Task 1.3: TodoExecutor 目标解析改为返回 world pos + 距离交互

**Files:**
- Modify: `scripts/npc/TodoExecutor.gd:76-99`(`_target_cell` → 新增 `_target_world_pos`)、`:95-96`(wander)、`:97-98`(rest)、`:190-194`(`_wander_cell`)
- Test: `apr/npc-loop/oracle/npc_loop_oracle.gd`(BLOCKED 用例重写,见 Task 1.5)+ 新断言

设计:新增 `_target_world_pos(todo, context, npc) -> Dictionary` 返回 `{ok, world_pos, interact_target}`:
- `inspect_item` / `talk_to_npc`:`world_pos` = 目标实体 `position`,`interact_target` = 同上(NPC 走到半径内即可,不需站上去)。
- `visit_place`:`world_pos` = door_cell / interior 格中心,`interact_target` = 同。
- `rest`:`world_pos` = NPC 当前 `position`(原地),`interact_target` = 同 → 立即 interacting=true → done。
- `wander`:随机选一个 walkable 且非当前格的格中心。

> 这是 P1 的行为改动核心。`execute_todo` 在 P1 不再"一拍 done",改为"begin_move + 由 tick 驱动 advance 直到 arrived/interacting 才 done"(见 Task 1.4 改 MainGame.tick_npc_execution)。但 `execute_todo` 作为"发起"语义保留;新增 `start_or_continue` 语义放在 MainGame 层。

- [ ] **Step 1: 写失败断言(rest 原地 done + wander 非当前格)**

新建 `apr/npc-loop/oracle/intent_resolve_oracle.gd`:
```gdscript
extends SceneTree

const PASS_MARKER := "INTENT_RESOLVE_ORACLE: PASS"
const FAIL_MARKER := "INTENT_RESOLVE_ORACLE: FAIL"

const TodoExecutorScript := preload("res://scripts/npc/TodoExecutor.gd")
const GridPathfinderScript := preload("res://scripts/world/GridPathfinder.gd")
const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ItemStateScript := preload("res://scripts/state/ItemState.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")
const ConstantsScript := preload("res://scripts/core/Constants.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 24, 16))
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 24, 16))
	var npc = NPCStateScript.from_dict({"id": "npc_a", "position": {"x": 48.0, "y": 48.0}})
	registry.add_npc(npc)
	var item = ItemStateScript.from_dict({"id": "it_a", "position": {"x": 240.0, "y": 240.0}})
	registry.add_item(item)
	var executor = TodoExecutorScript.new()
	executor.configure(registry, null, pathfinder, null)
	var ctx := {"entity_registry": registry, "place_registry": null, "pathfinder": pathfinder, "event_log": null, "mover": null}

	# rest:原地 = NPC 当前 position。
	var rest_todo = TodoItemScript.from_dict({"id": "t_rest", "intent": "rest", "status": "pending"})
	var rest = executor._target_world_pos(rest_todo, ctx, npc)
	_assert_true(bool(rest.get("ok", false)), "rest resolves ok")
	_assert_true(rest.get("world_pos") == npc.position, "rest target is npc current position")

	# inspect_item:interact_target = item position(不要求站上去)。
	var insp_todo = TodoItemScript.from_dict({"id": "t_insp", "intent": "inspect_item", "target_item_id": "it_a", "status": "pending"})
	var insp = executor._target_world_pos(insp_todo, ctx, npc)
	_assert_true(bool(insp.get("ok", false)), "inspect resolves ok")
	_assert_true(insp.get("interact_target") == item.position, "inspect interact_target is item position")

	# wander:选 walkable 且非当前格。
	var wan_todo = TodoItemScript.from_dict({"id": "t_wan", "intent": "wander", "status": "pending"})
	var wan = executor._target_world_pos(wan_todo, ctx, npc)
	_assert_true(bool(wan.get("ok", false)), "wander resolves ok")
	var wan_cell := ConstantsScript.world_to_cell(wan.get("world_pos"))
	_assert_true(wan_cell != npc.current_cell, "wander target cell differs from current, got %s" % str(wan_cell))


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/npc-loop/oracle/intent_resolve_oracle.gd`
Expected: FAIL —— `_target_world_pos` 不存在。

- [ ] **Step 3: 实现 _target_world_pos + 改 wander**

`scripts/npc/TodoExecutor.gd` 加方法(`_target_cell` 之后):
```gdscript
func _target_world_pos(todo, context: Dictionary, npc) -> Dictionary:
	if todo.intent == &"rest":
		return {"ok": true, "world_pos": npc.position, "interact_target": npc.position}
	if todo.intent == &"wander":
		var wcell: Vector2i = _wander_cell_continuous(context, npc)
		if wcell == ConstantsScript.INVALID_CELL:
			# 选不到别的格 → 原地 wander 视为达成,不 BLOCKED。
			return {"ok": true, "world_pos": npc.position, "interact_target": npc.position}
		var wpos: Vector2 = ConstantsScript.cell_to_world_center(wcell)
		return {"ok": true, "world_pos": wpos, "interact_target": wpos}
	if todo.intent == &"inspect_item":
		var items = context["entity_registry"].get("items") if context["entity_registry"] != null else {}
		if not items.has(todo.target_item_id):
			return {"ok": false}
		var ipos: Vector2 = items[todo.target_item_id].position
		return {"ok": true, "world_pos": ipos, "interact_target": ipos}
	if todo.intent == &"talk_to_npc":
		var npcs = context["entity_registry"].get("npcs") if context["entity_registry"] != null else {}
		if not npcs.has(todo.target_npc_id):
			return {"ok": false}
		var npos: Vector2 = npcs[todo.target_npc_id].position
		return {"ok": true, "world_pos": npos, "interact_target": npos}
	if todo.intent == &"visit_place":
		var cell: Vector2i = _target_cell(todo, context)
		if cell == ConstantsScript.INVALID_CELL:
			return {"ok": false}
		var ppos: Vector2 = ConstantsScript.cell_to_world_center(cell)
		return {"ok": true, "world_pos": ppos, "interact_target": ppos}
	return {"ok": false}


func _wander_cell_continuous(context: Dictionary, npc) -> Vector2i:
	var pf = context["pathfinder"]
	if pf == null:
		return ConstantsScript.INVALID_CELL
	var bounds: Rect2i = pf.get("map_bounds")
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return ConstantsScript.INVALID_CELL
	var current: Vector2i = ConstantsScript.world_to_cell(npc.position)
	# 确定性地选当前格右侧第一个 walkable 且非当前格的格(无 rng 依赖,oracle 可断言)。
	for dx in [1, -1, 2, -2, 3, -3]:
		var cand := Vector2i(current.x + dx, current.y)
		if bounds.has_point(cand) and pf.is_walkable(cand) and cand != current:
			return cand
	for dy in [1, -1, 2, -2]:
		var cand := Vector2i(current.x, current.y + dy)
		if bounds.has_point(cand) and pf.is_walkable(cand) and cand != current:
			return cand
	return ConstantsScript.INVALID_CELL
```

> 注意:`_wander_cell_continuous` 用确定性扫描而非随机,让 oracle 可断言"非当前格"。spec 写"随机选",这里用确定性实现满足"非当前格 + walkable"的本质要求,且可测;若要真随机,P3 可加 rng 注入(YAGNI,暂不做)。

- [ ] **Step 4: 跑 oracle 确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/npc-loop/oracle/intent_resolve_oracle.gd`
Expected: `INTENT_RESOLVE_ORACLE: PASS`

- [ ] **Step 5: Commit**

```bash
git add scripts/npc/TodoExecutor.gd apr/npc-loop/oracle/intent_resolve_oracle.gd
git commit -m "feat(p1): TodoExecutor resolves world pos + interact target (rest/wander/inspect/talk/visit)"
```

---

### Task 1.4: MainGame.tick_npc_execution 改为决策 + 逐帧推进

**Files:**
- Modify: `scripts/MainGame.gd:85-93`(_process 加 advance)、`:332-380`(tick_npc_execution / _tick_one_npc / _mover_for)
- Modify: `apr/npc-loop/oracle/npc_execution_loop_oracle.gd:69-83`(断言改 N 帧到达)

设计:NPC 执行从"tick 内瞬移 done"改为状态机:
- 每个 NPC 一个 mover(沿用 `_mover_for`)。`tick_npc_execution`(tick 节流调)= **决策层**:若 NPC 无 in-flight 移动且有 pending todo,解析目标 `_target_world_pos` → `mover.begin_move`,标 todo 为 in-progress(用 status `&"active"`)。
- `_process` 每帧 = **推进层**:对每个有 in-flight mover 的 NPC 调 `mover.advance(npc, delta)`;`arrived||interacting` 时标 todo `done` + 记完成事件 + 释放 lane。

- [ ] **Step 1: 改 npc_execution_loop oracle(失败测试)**

`apr/npc-loop/oracle/npc_execution_loop_oracle.gd`:把 `:69-83` 的"3 次 tick_npc_execution + 断言已移动 + done"改为驱动多帧:

```gdscript
	# v2: 移动是逐帧推进。先 tick 一次发起移动(决策),再驱动多帧推进。
	_assert_true(main.has_method("tick_npc_execution"), "MainGame has tick_npc_execution", failures)
	_assert_true(main.has_method("advance_npc_movement"), "MainGame has advance_npc_movement", failures)
	var start_pos = npc.position
	main.tick_npc_execution()                       # 决策:begin_move
	var arrived := false
	var frames := 0
	while frames < 300 and not arrived:
		main.advance_npc_movement(1.0 / 30.0)       # 推进
		if StringName(todo.status) == &"done":
			arrived = true
		frames += 1
	_assert_true(npc.position != start_pos, "npc moved continuously", failures)
	_assert_true(StringName(todo.status) == &"done", "todo done after arrival, frames=%d" % frames, failures)
```

> 沿用该 oracle 文件已有的 `_assert_true(cond, msg, failures)` 签名(见文件现有断言风格;若签名是 `_assert_true(cond, msg)`,去掉末参 failures)。

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/npc-loop/oracle/npc_execution_loop_oracle.gd`
Expected: FAIL —— `advance_npc_movement` 不存在 / todo 不再瞬间 done。

- [ ] **Step 3: 改 MainGame 执行状态机**

`scripts/MainGame.gd`:

`_process`(`:85`)在 sync 视觉层前加推进:
```gdscript
	advance_npc_movement(delta)
```

把 `tick_npc_execution`(`:332-337`)与 `_tick_one_npc`(`:339-362`)改为决策语义:
```gdscript
func tick_npc_execution() -> void:
	if entity_registry == null or todo_executor == null:
		return
	for npc in entity_registry.npcs.values():
		_decide_one_npc(npc)


# 决策:为没有 in-flight 移动且有 pending todo 的 NPC 发起一次移动。
func _decide_one_npc(npc) -> void:
	if npc == null or not (npc.todo_list is Array):
		return
	var mover = _mover_for(npc)
	if not mover.is_idle():
		return  # 正在走,等推进完成
	var todo = _next_pending_todo(npc)
	if todo == null:
		return
	var lane_action := {"id": StringName("exec_%s_%s" % [str(npc.id), str(todo.id)]), "npc_id": npc.id, "lane": &"movement"}
	if action_scheduler != null:
		var lane_result: Dictionary = action_scheduler.start_action(lane_action)
		if not bool(lane_result.get("accepted", false)):
			return
	var ctx := {"entity_registry": entity_registry, "place_registry": place_registry, "pathfinder": pathfinder, "event_log": event_log, "mover": mover}
	var resolved: Dictionary = todo_executor._target_world_pos(todo, ctx, npc)
	if not bool(resolved.get("ok", false)):
		todo_executor.mark_todo_blocked(npc, todo)
		if action_scheduler != null:
			action_scheduler.finish_action(npc.id, &"movement")
		return
	mover.begin_move(npc, resolved.get("world_pos"), resolved.get("interact_target"), todo)
	todo.status = &"active"
	# 头顶气泡:开始执行时显示 todo.reason(P3.4 接线点,P1 先接 reason)。
	if entity_visual_layer != null and entity_visual_layer.npc_visuals.has(npc.id):
		entity_visual_layer.npc_visuals[npc.id].show_bubble(str(todo.reason))


# 推进:每帧驱动所有 in-flight NPC 的连续移动,到达即完成 todo。
func advance_npc_movement(delta: float) -> void:
	if entity_registry == null:
		return
	for npc in entity_registry.npcs.values():
		var mover = npc_movers.get(npc.id)
		if mover == null or mover.is_idle():
			continue
		var r: Dictionary = mover.advance(npc, delta)
		if bool(r.get("arrived", false)) or bool(r.get("interacting", false)):
			_complete_active_todo(npc, mover)


func _complete_active_todo(npc, mover) -> void:
	var todo = mover.current_todo
	if todo != null:
		todo.status = &"done"
		if event_log != null and event_log.has_method("record"):
			event_log.record(&"npc_completed_todo", npc.id, &"", &"cell", npc.current_cell, {"todo_id": todo.id}, &"system", tick)
	if action_scheduler != null:
		action_scheduler.finish_action(npc.id, &"movement")
	mover.waypoints = []
```

> `_next_pending_todo`(`:365`)的判定是 `status == &"pending"`;我们把发起后的 todo 标 `&"active"`,完成标 `&"done"`,所以不会被重复发起。保留 `_next_pending_todo` 不变。

- [ ] **Step 4: 跑 npc_execution_loop oracle 确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/npc-loop/oracle/npc_execution_loop_oracle.gd`
Expected: `NPC_EXECUTION_LOOP_ORACLE: PASS`

- [ ] **Step 5: 清理 P0 临时桥接**

P1 后 position 由 `advance` 写,Task 0.4 Step 5 在 `_move_npc_to_cell`/`_move_item_to_cell` 加的 `position = cell_to_world_center(...)` 桥接对 NPC 移动已冗余 —— 但**保留 item 的桥接**(拖拽/drop 在 P2 才改连续,P1 期间 item 仍走 move_entity_to_cell)。只在确认 NPC 移动全走 advance 后,可留着不删(无害);本步不强制删,记一笔留待 P2 统一清理。

- [ ] **Step 6: 跑全部单测 + playable-ui 确认未回归**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`

Run: `python apr/playable-ui/oracle/run_playable_ui_oracle.py`
Expected: PASS(若 runner 静态断言要求 `tick_npc_execution` 字样仍在 —— 仍在;新增 `advance_npc_movement` 不破坏)。

- [ ] **Step 7: Commit**

```bash
git add scripts/MainGame.gd apr/npc-loop/oracle/npc_execution_loop_oracle.gd
git commit -m "feat(p1): tick=decide + per-frame advance; continuous movement, distance interaction"
```

---

### Task 1.5: 重写 npc_loop oracle 的 BLOCKED 用例(真不可达)

**Files:**
- Modify: `apr/npc-loop/oracle/npc_loop_oracle.gd:123-147`(`_test_todo_executor_blocks_or_falls_back`)、`:150-172`(`_make_world`)
- Modify: `tests/test_core_behaviors.gd:459`(`_test_todo_executor_blocks_and_adds_fallback`,若依赖旧"同格被占"语义)

设计:旧 BLOCKED 用例靠"目标=被占格"触发,现在距离交互已不靠占格 → 该触发失效。改用**真正不可达**:用建筑 fence 把目标格完全围死(`set_solid_cell` 四周),NPC 无路可达 → `begin_move` 后 waypoints 为空且不在交互半径 → 标 BLOCKED。

- [ ] **Step 1: 改写 oracle 的 BLOCKED 用例(失败测试)**

`apr/npc-loop/oracle/npc_loop_oracle.gd` 的 `_test_todo_executor_blocks_or_falls_back`(`:123-147`):改为造一个被 solid_cells 围死的 visit_place 目标,断言:发起后 `mover.is_idle()` 且 NPC 未达交互半径时,executor 标 todo BLOCKED 并追加 fallback。

```gdscript
func _test_todo_executor_blocks_or_falls_back() -> void:
	var pathfinder = GridPathfinderScript.new()
	pathfinder.set_map_bounds(Rect2i(0, 0, 24, 16))
	# 把 (5,5) 四周全设 solid,使其从 (1,1) 真正不可达。
	for c in [Vector2i(4,5), Vector2i(6,5), Vector2i(5,4), Vector2i(5,6)]:
		pathfinder.set_solid_cell(c, true)
	var registry = WorldEntityRegistryScript.new()
	registry.set_map_bounds(Rect2i(0, 0, 24, 16))
	var npc = NPCStateScript.from_dict({"id": "npc_blk", "position": {"x": 48.0, "y": 48.0}})
	registry.add_npc(npc)
	var mover = NPCMoverScript.new()
	mover.configure(registry, null, pathfinder, null)
	var goal := ConstantsScript.cell_to_world_center(Vector2i(5, 5))
	mover.begin_move(npc, goal, goal, null)
	# 不可达:无航点,且起点不在目标交互半径内。
	_assert_true(mover.is_idle(), "unreachable target yields no waypoints")
	_assert_true(npc.position.distance_to(goal) > ConstantsScript.INTERACT_RADIUS, "npc not already within interact radius")
	# executor 标 BLOCKED + 追加 fallback。
	var executor = TodoExecutorScript.new()
	executor.configure(registry, null, pathfinder, null)
	var todo = TodoItemScript.from_dict({"id": "t_blk", "intent": "visit_place", "target_place_id": "nope", "status": "pending"})
	npc.todo_list = [todo]
	executor.mark_todo_blocked(npc, todo)
	_assert_true(StringName(todo.status) == &"BLOCKED", "todo marked BLOCKED")
	_assert_true(npc.todo_list.size() >= 2, "fallback todo appended")
```

> 该 oracle 文件顶部需有 `NPCMoverScript`/`ConstantsScript`/`GridPathfinderScript`/`WorldEntityRegistryScript`/`NPCStateScript`/`TodoItemScript` 的 preload;若缺,在文件 const 区补 preload(参照其他 oracle 的 preload 写法)。

- [ ] **Step 2: 跑 oracle 确认失败→通过**

Run: `python apr/npc-loop/oracle/run_npc_loop_oracle.py`
先确认改完前后:改测试后先跑应能 PASS(因为 `mark_todo_blocked` + `_ensure_fallback_todo` 已存在,`begin_move` 在 Task 1.2 已实现)。若 FAIL,按报错补 preload 或调断言。
Expected: `NPC_LOOP_ORACLE: PASS`

- [ ] **Step 3: 修 test_core_behaviors 里依赖旧 BLOCKED 语义的单测**

检查 `tests/test_core_behaviors.gd:459` `_test_todo_executor_blocks_and_adds_fallback`:它造"缺失目标 todo→BLOCKED+fallback"。这个语义在 v2 仍成立(`_target_world_pos` 返回 `{ok:false}` → MainGame 标 BLOCKED),**无需改**。仅当它直接断言 occupancy 才需动 —— 据勘探它不碰 occupancy,确认后跳过。

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`

- [ ] **Step 4: Commit**

```bash
git add apr/npc-loop/oracle/npc_loop_oracle.gd
git commit -m "test(p1): rewrite BLOCKED oracle to use truly-unreachable target (not occupancy)"
```

---

**P1 完成验收:** NPC 连续平滑移动(逐帧 advance);交互靠距离阈值;rest 原地 done、wander 选非当前格、inspect/talk 走到目标旁 done —— 3 个 BLOCKED bug 化解;BLOCKED oracle 改测真不可达。全部 oracle + 单测绿。

---

## P2 · occupancy 移除 + 拖拽重力感 + 视觉选中 + 建筑避让改遍历

P2 目标:移除 `npc_occupancy`/`item_occupancy` 占用表;`set_entity_position(id, pos)` 取代 `move_entity_to_cell` 的占用校验语义;拖拽改重力感跟随鼠标(松手落连续点);选中改视觉 hit-test;建筑避让改遍历 NPC position 投影格。

**回归面最大,按铁律 2 逐 oracle pre→post 更新。** 这一阶段会删 `test_core_behaviors` 的同格去重/rebuild 测试、改 `verify_project.py` 方法表。

### Task 2.1: WorldEntityRegistry 增加 set_entity_position(连续写位置)

**Files:**
- Modify: `scripts/world/WorldEntityRegistry.gd`(加 `set_entity_position` / `set_npc_position` / `set_item_position`)
- Test: 新建 `apr/continuous-move/oracle/set_position_oracle.gd`

设计:`set_entity_position(entity_id, pos: Vector2) -> bool`:写实体 `position` + 派生 `current_cell = world_to_cell(pos)`;若投影格是建筑墙(`blocked_cells`)则推到最近非墙连续点;不再查占用、不拒重叠。先与旧 `move_entity_to_cell` 并存(P2.5 移除占用后,旧方法内部改调它或删除)。

- [ ] **Step 1: 写失败 oracle**

Create `apr/continuous-move/oracle/set_position_oracle.gd`:
```gdscript
extends SceneTree

const PASS_MARKER := "SET_POSITION_ORACLE: PASS"
const FAIL_MARKER := "SET_POSITION_ORACLE: FAIL"

const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ConstantsScript := preload("res://scripts/core/Constants.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var reg = WorldEntityRegistryScript.new()
	reg.set_map_bounds(Rect2i(0, 0, 24, 16))
	reg.add_npc(NPCStateScript.from_dict({"id": "npc_a", "position": {"x": 48.0, "y": 48.0}}))
	reg.add_npc(NPCStateScript.from_dict({"id": "npc_b", "position": {"x": 200.0, "y": 48.0}}))

	# 设连续位置:position 真相 + current_cell 派生。
	var ok = reg.set_entity_position(StringName("npc_a"), Vector2(100, 60))
	_assert_true(ok, "set_entity_position returns true")
	var a = reg.npcs[StringName("npc_a")]
	_assert_true(a.position == Vector2(100, 60), "npc_a position written")
	_assert_true(a.current_cell == ConstantsScript.world_to_cell(Vector2(100, 60)), "npc_a current_cell derived")

	# 允许重叠:把 npc_b 设到与 npc_a 完全相同的连续位置,不拒绝。
	var ok2 = reg.set_entity_position(StringName("npc_b"), Vector2(100, 60))
	_assert_true(ok2, "overlap allowed (no occupancy rejection)")
	_assert_true(reg.npcs[StringName("npc_b")].position == Vector2(100, 60), "npc_b at same pos as npc_a")


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/continuous-move/oracle/set_position_oracle.gd`
Expected: FAIL —— `set_entity_position` 不存在。

- [ ] **Step 3: 实现 set_entity_position**

`scripts/world/WorldEntityRegistry.gd` 加方法:
```gdscript
func set_entity_position(entity_id: StringName, pos: Vector2) -> bool:
	if npcs.has(entity_id):
		return set_npc_position(entity_id, pos)
	if items.has(entity_id):
		return set_item_position(entity_id, pos)
	return false


func set_npc_position(npc_id: StringName, pos: Vector2) -> bool:
	if not npcs.has(npc_id):
		return false
	var resolved: Vector2 = _resolve_walkable_position(pos)
	var npc = npcs[npc_id]
	npc.position = resolved
	npc.current_cell = ConstantsScript.world_to_cell(resolved)
	return true


func set_item_position(item_id: StringName, pos: Vector2) -> bool:
	if not items.has(item_id):
		return false
	var item = items[item_id]
	if item.held_by_npc_id != &"":
		return false
	var resolved: Vector2 = _resolve_walkable_position(pos)
	item.position = resolved
	item.current_cell = ConstantsScript.world_to_cell(resolved)
	return true


# 若投影格是建筑墙,推到最近非墙格中心;否则原样返回连续 pos。
func _resolve_walkable_position(pos: Vector2) -> Vector2:
	var cell: Vector2i = ConstantsScript.world_to_cell(pos)
	if not blocked_cells.has(cell) and _is_cell_in_bounds(cell):
		return pos
	# 螺旋找最近非墙且在界内的格,返回其中心。
	var max_radius = max(map_bounds.size.x, map_bounds.size.y)
	for radius in range(1, max_radius + 1):
		for y in range(cell.y - radius, cell.y + radius + 1):
			for x in range(cell.x - radius, cell.x + radius + 1):
				if max(abs(x - cell.x), abs(y - cell.y)) != radius:
					continue
				var cand := Vector2i(x, y)
				if _is_cell_in_bounds(cand) and not blocked_cells.has(cand):
					return ConstantsScript.cell_to_world_center(cand)
	return pos
```

- [ ] **Step 4: 跑 oracle 确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/continuous-move/oracle/set_position_oracle.gd`
Expected: `SET_POSITION_ORACLE: PASS`

- [ ] **Step 5: 跑全部单测确认未回归**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`(纯新增方法,旧 occupancy 仍在,现有测试不受影响)。

- [ ] **Step 6: Commit**

```bash
git add scripts/world/WorldEntityRegistry.gd apr/continuous-move/oracle/set_position_oracle.gd
git commit -m "feat(p2): set_entity_position writes continuous pos, allows overlap"
```

---

### Task 2.2: 移除 occupancy 表 + 简化 validate/rebuild/drop

**Files:**
- Modify: `scripts/world/WorldEntityRegistry.gd`(删 `npc_occupancy`/`item_occupancy` 及相关)
- Modify: `tools/verify_project.py:81-104`(WorldEntityRegistry 字段/方法期望)
- Modify: `tests/test_core_behaviors.gd`(删/改依赖 occupancy 的测试)

设计:删占用表与同格逻辑。`get_npc_at_cell`/`get_item_at_cell` 改为遍历实体按 `world_to_cell(position)` 匹配(供建筑避让用,返回首个命中);`validate_forced_drop` 去掉占用两条检查;`_move_npc_to_cell`/`_move_item_to_cell` 改为调 `set_npc_position`/`set_item_position`(用格中心);`_rebuild_occupancy`/同格去重删除;`repair_inventory_links` 保留持有一致性、去掉 `_rebuild_occupancy` 调用;`drop_held_item` 落点改持有者 position 附近。`find_nearest_free_cell` 删除(无消费者后)。

- [ ] **Step 1: 改 test_core_behaviors —— 删/改 occupancy 测试(失败测试先行)**

`tests/test_core_behaviors.gd`:

**删除**整个 `_test_rebuild_occupancy_repairs_duplicate_cells`(`:240` 起的函数)及其在 `run()` 里的调用 —— 连续世界无"同格去重"概念。

**改** `_test_item_drop_to_empty_cell_updates_cell_and_occupancy`(`:136`):去掉 `get_item_at_cell` 旧格清空断言(`:143-144`),改为断言 `set_entity_position` 后 item.position 更新:
```gdscript
func _test_item_drop_updates_position(failures: Array) -> void:
	var reg = WorldEntityRegistryScript.new()
	reg.set_map_bounds(Rect2i(0, 0, 24, 16))
	reg.add_item(ItemStateScript.from_dict({"id": "it", "position": {"x": 16.0, "y": 16.0}}))
	var ok = reg.set_entity_position(StringName("it"), Vector2(80, 80))
	_expect_true(failures, ok, "set item position ok")
	_expect_equal(failures, reg.items[StringName("it")].position, Vector2(80, 80), "item position updated")
```
(在 `run()` 里把旧调用替换为 `_test_item_drop_updates_position(failures)`。)

**改** `_test_save_load_repair_prefers_npc_inventory`(`:199`):删 `get_item_at_cell` 网格断言(`:215`),保留 repair_warnings + 持有一致性断言。

**改** `_test_repair_duplicate_npc_inventory_chooses_deterministic_winner`(`:220`):这是**持有去重**(两 NPC 持同一 item),与 occupancy 无关,**保留**;只确认它不调 `get_npc_at_cell`/occupancy。

**删** `_test_second_item_on_holding_npc...`(`:161`)里的 `get_item_at_cell` occupancy 断言(`:175`),保留"拒绝第二件 + 无字段变动"主断言。

**删** `_test_right_click_discard...`(`:178`)的 `get_item_at_cell((1,1))` 断言(`:190`),改为断言 drop 后 item.position 在持有者附近(见 Task 2.4 的 drop 落点)。

- [ ] **Step 2: 跑测试确认失败**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: FAIL —— 改后的测试引用了尚未实现的行为(set_entity_position 已有,但删 occupancy 后 get_item_at_cell 行为变 / rebuild 测试删了)。先确保测试文件能加载;真正的红来自下一步删 occupancy 前的过渡态。

- [ ] **Step 3: 删 occupancy 表与相关方法**

`scripts/world/WorldEntityRegistry.gd`:

删字段 `:12-13`(`npc_occupancy`/`item_occupancy`)。

`get_npc_at_cell`/`get_item_at_cell`(`:40-45`)改为遍历:
```gdscript
func get_npc_at_cell(cell: Vector2i) -> StringName:
	for npc_id in npcs.keys():
		if ConstantsScript.world_to_cell(npcs[npc_id].position) == cell:
			return StringName(npc_id)
	return &""


func get_item_at_cell(cell: Vector2i) -> StringName:
	for item_id in items.keys():
		var item = items[item_id]
		if item.held_by_npc_id == &"" and ConstantsScript.world_to_cell(item.position) == cell:
			return StringName(item_id)
	return &""
```

`validate_forced_drop`(`:48-59`)删占用两条(`:55-58`),保留越界 + 建筑墙。

`add_npc`/`add_item`(`:28-37`)删 occupancy 写入(`:30-31`、`:36-37`),只保留 `npcs[npc.id] = npc` / `items[item.id] = item`。

`give_item_to_npc`(`:84-85`)删 `item_occupancy.erase`;保留清 position:`item.position = Vector2.ZERO`。

`drop_held_item`:见 Task 2.4(本步先让其用 `set_item_position`,落点暂用 `find_nearest_free_cell` 的格中心 → 下步 2.4 改连续)。临时:把 `:104` `item_occupancy[target_cell] = item_id` 删掉。

`move_entity_to_cell`(`:62-67`)改为转调 set_position(格中心):
```gdscript
func move_entity_to_cell(entity_id: StringName, target_cell: Vector2i) -> bool:
	return set_entity_position(entity_id, ConstantsScript.cell_to_world_center(target_cell))
```

`_move_npc_to_cell`/`_move_item_to_cell`(`:204-227`)删除(被 `move_entity_to_cell` 转调取代)。

`_is_free_cell`(`:230-239`)删 occupancy 两条(`:235-237`),只判界 + 建筑墙。

`_rebuild_occupancy`(`:255-263`)、`_place_npc_during_rebuild`(`:299-311`)、`_place_item_during_rebuild`(`:314-326`)**删除**。

`repair_inventory_links`(`:158`)删 `_rebuild_occupancy()` 调用。

`load_from_dict`(`:175-176`)删 `npc_occupancy.clear()`/`item_occupancy.clear()`。

- [ ] **Step 4: 更新 verify_project 方法/字段表**

`tools/verify_project.py:81-104` WorldEntityRegistry 期望:
- fields:删 `"npc_occupancy",`、`"item_occupancy",`(`:86-87`)。
- methods:删 `"find_nearest_free_cell",`(`:99`);加 `"set_entity_position",`。保留 `validate_forced_drop`/`move_entity_to_cell`(仍存在,语义已改)。

> 若 `find_nearest_free_cell` 仍被 `drop_held_item` 用(Task 2.4 前),暂保留方法表里的它;2.4 删除后再从表里删。本步:加 `set_entity_position`,删两个 occupancy 字段。

- [ ] **Step 5: 跑测试 + verify + 所有 oracle**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`

Run: `python tools/verify_project.py`
Expected: `VERIFY_PROJECT: PASS`

Run: `python apr/npc-loop/oracle/run_npc_loop_oracle.py` 和 `python apr/place-registry-walkable/oracle/run_place_registry_walkable_oracle.py`
Expected: 均 PASS(place-registry 不碰 occupancy;npc-loop 已在 P1 改)。

- [ ] **Step 6: Commit**

```bash
git add scripts/world/WorldEntityRegistry.gd tools/verify_project.py tests/test_core_behaviors.gd
git commit -m "feat(p2): remove occupancy tables; positions allow overlap; cell queries derive from position"
```

---

### Task 2.3: 建筑放置 NPC 避让改遍历 position

**Files:**
- Modify: `scripts/world/BuildingPlacementService.gd:178-188`(`get_npcs_occupying_cells`)
- Test: `tests/test_core_behaviors.gd:332`(`_test_placement_rejects_npc_current_occupancy`)

设计:`get_npcs_occupying_cells` 不再调 `get_npc_at_cell`(已改遍历,但语义保留),实际可保持调用——`get_npc_at_cell` 在 2.2 已改为按 position 投影格匹配,所以 `get_npcs_occupying_cells` **自动正确**,无需改逻辑。但为清晰,直接遍历 NPC:

- [ ] **Step 1: 确认现有测试仍覆盖(可能已绿)**

`_test_placement_rejects_npc_current_occupancy`(`:332`):把 NPC 放在 footprint 内的格,断言 `can_place_fenced_area` 拒绝 `npc_occupies_footprint`。NPC 现在用 position;测试需确保 NPC position 投影格落在 footprint 内。检查测试:若它用 `current_cell` 造 NPC,因 `from_dict` 会派生 position,投影格一致,**测试自动成立**。

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`。若该测试 FAIL(因 NPC 构造方式),改为用 position 构造 NPC 落在 footprint 内的格中心。

- [ ] **Step 2: (可选)显式遍历重写 get_npcs_occupying_cells**

为不依赖 `get_npc_at_cell` 的副作用,直接遍历:
```gdscript
func get_npcs_occupying_cells(cells: Array) -> Array:
	var result: Array = []
	if entity_registry == null:
		return result
	var cell_set: Dictionary = {}
	for cell in cells:
		cell_set[cell] = true
	for npc_id in entity_registry.npcs.keys():
		var npc = entity_registry.npcs[npc_id]
		var ncell: Vector2i = ConstantsScript.world_to_cell(npc.position)
		if cell_set.has(ncell):
			result.append(StringName(npc_id))
	return _sorted_string_names(result)
```

- [ ] **Step 3: 跑测试 + place oracle 确认通过**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`

- [ ] **Step 4: Commit**

```bash
git add scripts/world/BuildingPlacementService.gd tests/test_core_behaviors.gd
git commit -m "feat(p2): building footprint NPC-avoidance iterates NPC positions"
```

---

### Task 2.4: 拖拽重力感 + drop 落连续点 + 视觉 hit-test 选中

**Files:**
- Modify: `scripts/MainGame.gd`(`select_cell_target`/`start_drag_grab`/`update_drag_preview`/`drop_or_release_selection`,`:157-209`;`_process` 拖拽推进;`discard`)
- Modify: `scripts/world/WorldEntityRegistry.gd`(`drop_held_item` 落点改连续)
- Modify: `scripts/ui/GridSelectionOverlay.gd`(暴露鼠标 world pos,见下)
- Test: 新建 `apr/drag-gravity/oracle/drag_gravity_oracle.gd`

设计:
- **选中(视觉 hit-test):** 点击点 world pos → 遍历 NPCVisual/ItemVisual,取离点击点 < 命中半径且最近者。
- **拖拽重力感:** 拖拽中记 `grabbed_entity_id` + `grab_mouse_world`;`_process` 每帧把被拖实体 position 朝 `grab_mouse_world` 弹性插值(`pos += (mouse - pos) * GRAB_PULL`,`GRAB_PULL=0.2`)。
- **松手:** `set_entity_position(grabbed, current_pos)`(落连续点,墙内则推开);若落点命中某 NPC 且拖的是 item → `give_item_to_npc`。
- **drop_held_item 落点:** 改为持有者 position + 偏移(右侧 0.6 格),用 `set_item_position`。

> 选中/拖拽需要鼠标的 **world 坐标**。`GridSelectionOverlay` 现在发的是 cell(Vector2i)。新增信号或在 MainGame 用 `get_global_mouse_position()` 配合 camera 取 world pos。为最小改动:MainGame 在 `_process` 用 `world_map.get_local_mouse_position()` 取 world pos(WorldMap 是世界坐标系父节点)。

- [ ] **Step 1: 写失败 oracle(重力感 + 选中 hit-test)**

Create `apr/drag-gravity/oracle/drag_gravity_oracle.gd`:
```gdscript
extends SceneTree

const PASS_MARKER := "DRAG_GRAVITY_ORACLE: PASS"
const FAIL_MARKER := "DRAG_GRAVITY_ORACLE: FAIL"

const WorldEntityRegistryScript := preload("res://scripts/world/WorldEntityRegistry.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const ConstantsScript := preload("res://scripts/core/Constants.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	# 重力感:position 朝鼠标弹性插值,逐步逼近但不瞬移。
	var reg = WorldEntityRegistryScript.new()
	reg.set_map_bounds(Rect2i(0, 0, 24, 16))
	reg.add_npc(NPCStateScript.from_dict({"id": "npc_a", "position": {"x": 48.0, "y": 48.0}}))
	var npc = reg.npcs[StringName("npc_a")]
	var mouse := Vector2(300, 300)
	var pull := 0.2
	var start_dist := npc.position.distance_to(mouse)
	# 模拟 5 帧弹性拖拽。
	for i in range(5):
		npc.position += (mouse - npc.position) * pull
	var after_dist := npc.position.distance_to(mouse)
	_assert_true(after_dist < start_dist, "gravity pulls toward mouse (%.1f -> %.1f)" % [start_dist, after_dist])
	_assert_true(after_dist > 0.0, "not teleported instantly to mouse")

	# 松手落连续点(允许任意像素,不 snap 到格中心)。
	reg.set_entity_position(StringName("npc_a"), Vector2(137, 91))
	_assert_true(reg.npcs[StringName("npc_a")].position == Vector2(137, 91), "drop lands at continuous pixel pos")


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

- [ ] **Step 2: 跑 oracle 确认通过(纯算法验证,无需新代码即可绿)**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/drag-gravity/oracle/drag_gravity_oracle.gd`
Expected: `DRAG_GRAVITY_ORACLE: PASS`(验证重力感公式 + set_entity_position 落连续点;此 oracle 锁定算法契约,MainGame 接线在 Step 3-5)。

- [ ] **Step 3: MainGame 选中改视觉 hit-test**

`scripts/MainGame.gd`:加成员:
```gdscript
const GRAB_PULL := 0.2
const HIT_RADIUS := 18.0
var grab_mouse_world: Vector2 = Vector2.ZERO
```

`select_cell_target`(`:157-173`)改为视觉 hit-test(参数仍收 cell 以兼容信号,但用 world pos 命中):
```gdscript
func select_cell_target(cell: Vector2i) -> void:
	last_selected_cell = cell
	var click_world: Vector2 = ConstantsScript.cell_to_world_center(cell)
	if grid_selection_overlay != null and grid_selection_overlay.has_method("get_last_click_world"):
		click_world = grid_selection_overlay.get_last_click_world()
	var hit_id := _hit_test_entity(click_world)
	if hit_id != &"":
		selected_entity_id = hit_id
		grabbed_entity_id = hit_id
		grab_mouse_world = click_world
		_update_selected_highlight()
		_update_feedback_text("Selected %s" % str(hit_id))
		return
	selected_entity_id = &""
	grabbed_entity_id = &""
	_update_selected_highlight()
	_update_feedback_text("Selected cell %s" % str(cell))


func _hit_test_entity(world_pos: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist: float = HIT_RADIUS
	for npc in entity_registry.npcs.values():
		var d: float = npc.position.distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best_id = npc.id
	for item in entity_registry.items.values():
		if item.held_by_npc_id != &"":
			continue
		var d: float = item.position.distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best_id = item.id
	return best_id


func _update_selected_highlight() -> void:
	if entity_visual_layer == null:
		return
	for npc_id in entity_visual_layer.npc_visuals.keys():
		var v = entity_visual_layer.npc_visuals[npc_id]
		v.selected = (npc_id == selected_entity_id)
		v.queue_redraw()
```

- [ ] **Step 4: MainGame 拖拽重力感 + 松手落连续点**

`_process`(`:85`)加拖拽推进(在 advance_npc_movement 后):
```gdscript
	_apply_drag_gravity()
```
```gdscript
func _apply_drag_gravity() -> void:
	if grabbed_entity_id == &"" or world_map == null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	grab_mouse_world = world_map.get_local_mouse_position()
	var ent = entity_registry.npcs.get(grabbed_entity_id)
	if ent == null:
		ent = entity_registry.items.get(grabbed_entity_id)
	if ent == null:
		return
	ent.position += (grab_mouse_world - ent.position) * GRAB_PULL
	ent.current_cell = ConstantsScript.world_to_cell(ent.position)
```

`drop_or_release_selection`(`:187-209`)改为松手落连续点:
```gdscript
func drop_or_release_selection(selection_rect: Rect2i, end_cell: Vector2i) -> void:
	latest_drag_rect = selection_rect
	latest_drag_end_cell = end_cell
	if fenced_area_mode:
		confirm_fenced_area_from_drag(selection_rect, end_cell)
		return
	if grabbed_entity_id == &"":
		return
	var drop_world: Vector2 = world_map.get_local_mouse_position() if world_map != null else ConstantsScript.cell_to_world_center(end_cell)
	# 拖 item 落到某 NPC 命中半径内 → 给物品。
	if entity_registry.items.has(grabbed_entity_id):
		var target_npc := _hit_test_npc_only(drop_world)
		if target_npc != &"":
			if entity_registry.give_item_to_npc(grabbed_entity_id, target_npc):
				event_log.record(&"player_drop_item_on_npc", grabbed_entity_id, target_npc, &"npc", ConstantsScript.world_to_cell(drop_world), {}, &"player", tick)
				_update_feedback_text("NPC accepted item")
				grabbed_entity_id = &""
				return
	if entity_registry.set_entity_position(grabbed_entity_id, drop_world):
		event_log.record(&"player_move_entity", grabbed_entity_id, &"", &"cell", ConstantsScript.world_to_cell(drop_world), {}, &"player", tick)
		_update_feedback_text("Dropped %s" % str(grabbed_entity_id))
	grabbed_entity_id = &""


func _hit_test_npc_only(world_pos: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist: float = HIT_RADIUS
	for npc in entity_registry.npcs.values():
		var d: float = npc.position.distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best_id = npc.id
	return best_id
```

- [ ] **Step 5: GridSelectionOverlay 暴露 last click world pos**

`scripts/ui/GridSelectionOverlay.gd`:在处理鼠标按下时记录 world pos,加 getter。在 `_unhandled_input` 的 `InputEventMouseButton` 左键按下分支(参照现有 `:23-33`)记录:
```gdscript
var _last_click_world: Vector2 = Vector2.ZERO


func get_last_click_world() -> Vector2:
	return _last_click_world
```
在左键按下处理里(发 `cell_clicked` 前)加:
```gdscript
	_last_click_world = get_local_mouse_position()
```
(GridSelectionOverlay 在 WorldMap 下,与实体同世界坐标系,`get_local_mouse_position` 即 world pos。)

- [ ] **Step 6: drop_held_item 落点改连续**

`scripts/world/WorldEntityRegistry.gd` `drop_held_item`(`:89-108`):落点改持有者 position 偏移:
```gdscript
	var holder_pos: Vector2 = npc.position
	var target_pos: Vector2 = holder_pos + Vector2(ConstantsScript.CELL_SIZE * 0.6, 0)
	npc.held_item_id = &""
	item.held_by_npc_id = &""
	item.position = _resolve_walkable_position(target_pos)
	item.current_cell = ConstantsScript.world_to_cell(item.position)
	if event_log != null and event_log.has_method("record"):
		event_log.record(&"player_forced_drop_item", item_id, npc_id, &"npc", item.current_cell)
	return true
```
删掉原 `find_nearest_free_cell` 落点逻辑(`:97-104`)。**此时 `find_nearest_free_cell` 无消费者** → 删除该方法(`:111-127`),并从 `verify_project.py` 方法表删 `"find_nearest_free_cell"`。

- [ ] **Step 6.5: 物品在手 reparent(第 4 项)+ oracle 断言**

`scripts/ui/EntityVisualLayer.gd._sync_items`:持有态的 item visual reparent 到持有者 NPCVisual 的 `HeldItemAnchor`,放下时 reparent 回 layer。改 `_sync_items`:
```gdscript
func _sync_items(entity_registry) -> void:
	for item_id in entity_registry.items.keys():
		var item = entity_registry.items[item_id]
		var visual = item_visuals.get(item_id)
		if visual == null:
			visual = ItemVisualScript.new()
			visual.item_id = item_id
			add_child(visual)
			item_visuals[item_id] = visual
		if item.held_by_npc_id != &"" and npc_visuals.has(item.held_by_npc_id):
			# 在手:挂到持有者 HeldItemAnchor,局部坐标归零。
			var anchor = npc_visuals[item.held_by_npc_id].get_node_or_null("HeldItemAnchor")
			if anchor != null and visual.get_parent() != anchor:
				visual.get_parent().remove_child(visual)
				anchor.add_child(visual)
				visual.position = Vector2.ZERO
		else:
			# 不在手:确保挂在 layer 下,position = item.position。
			if visual.get_parent() != self:
				visual.get_parent().remove_child(visual)
				add_child(visual)
			visual.position = item.position
	for item_id in item_visuals.keys().duplicate():
		if not entity_registry.items.has(item_id):
			item_visuals[item_id].queue_free()
			item_visuals.erase(item_id)
```

> 注意 sync 顺序:`sync_from_registry` 必须先 `_sync_npcs`(确保 NPCVisual/HeldItemAnchor 存在)再 `_sync_items`(reparent 到 anchor)。P0.3 的 `sync_from_registry` 已是此顺序。

在 `apr/entity-visual/oracle/entity_visual_oracle.gd._run()` 末尾加持有态断言:
```gdscript
	# 第4项:item 被持有时,其 visual 挂在持有者的 HeldItemAnchor 下。
	var reg3 = WorldEntityRegistryScript.new()
	reg3.set_map_bounds(Rect2i(0, 0, 24, 16))
	reg3.add_npc(NPCStateScript.from_dict({"id": "npc_h", "position": {"x": 48.0, "y": 48.0}}))
	reg3.add_item(ItemStateScript.from_dict({"id": "it_h", "position": {"x": 80.0, "y": 48.0}}))
	var layer3 = EntityVisualLayerScript.new()
	get_root().add_child(layer3)
	layer3.sync_from_registry(reg3)
	reg3.give_item_to_npc(StringName("it_h"), StringName("npc_h"))
	layer3.sync_from_registry(reg3)
	var iv = layer3.item_visuals[StringName("it_h")]
	var held_anchor = layer3.npc_visuals[StringName("npc_h")].get_node("HeldItemAnchor")
	_assert_true(iv.get_parent() == held_anchor, "held item visual reparented to HeldItemAnchor")
```

- [ ] **Step 7: 跑全部:单测 + verify + 所有 oracle**

Run: `powershell.exe -File tools/godot/run-tests.ps1` → `GODOT_TESTS: PASS`
Run: `python tools/verify_project.py` → `VERIFY_PROJECT: PASS`
Run: `python apr/npc-loop/oracle/run_npc_loop_oracle.py && python apr/playable-ui/oracle/run_playable_ui_oracle.py` → 各自 PASS
Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/drag-gravity/oracle/drag_gravity_oracle.gd` → PASS
Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/continuous-move/oracle/set_position_oracle.gd` → PASS
Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/entity-visual/oracle/entity_visual_oracle.gd` → PASS(含第 4 项持有 reparent 断言)

> playable-ui runner(`run_playable_ui_oracle.py:81-240`)若静态断言 MainGame 含 `get_npc_at_cell`/`get_item_at_cell` 选中字样 —— 现在选中改 hit-test,把那条断言改为校验 `_hit_test_entity`/`set_entity_position` 字样。

- [ ] **Step 8: Commit**

```bash
git add scripts/MainGame.gd scripts/world/WorldEntityRegistry.gd scripts/ui/GridSelectionOverlay.gd tools/verify_project.py apr/drag-gravity/oracle/ apr/playable-ui/oracle/
git commit -m "feat(p2): drag gravity follow + continuous drop + visual hit-test selection; remove find_nearest_free_cell"
```

---

**P2 完成验收:** occupancy 表移除;实体可同点重叠;拖拽有重力感跟随鼠标、松手落连续点;选中改视觉 hit-test;建筑避让遍历 position;drop 落持有者旁。全部 oracle + 单测 + verify_project 绿。

---

## P3 · 呈现 / 交互

P3 目标:草地地面 + 网格仅建造模式显示(第 1、2 项);非建造模式不画 drag-rect(第 7 项);滚轮 zoom(第 5 项);控制 UI 折叠提示(第 6 项);日程侧栏(第 8 项);头顶气泡内容接线(第 9 项);时钟驱动自动日程(第 8 项)。

### Task 3.1: 草地地面 + 网格仅建造模式显示

**Files:**
- Modify: `scripts/MainGame.gd:110-118`(_draw 网格)
- Modify: `scripts/ui/GridSelectionOverlay.gd`(网格绘制仅 fenced_area_mode)
- Test: `apr/playable-ui/oracle/run_playable_ui_oracle.py`(静态断言草地/网格条件)

设计:`MainGame._draw` 网格线改为草地底色矩形 + 仅当 `fenced_area_mode` 时画网格线。草地用 `draw_rect` 铺 map_bounds 区域(绿色)。

- [ ] **Step 1: 改 _draw —— 草地常驻 + 网格条件**

`scripts/MainGame.gd._draw`(`:110-118`)替换为:
```gdscript
func _draw() -> void:
	# 草地底色(常驻)。
	var origin := Vector2(map_bounds.position.x * cell_size, map_bounds.position.y * cell_size)
	var size := Vector2(map_bounds.size.x * cell_size, map_bounds.size.y * cell_size)
	draw_rect(Rect2(origin, size), Color(0.30, 0.55, 0.28, 1.0), true)
	# 网格线仅建造模式可见(用于定位建筑)。
	if fenced_area_mode:
		for x in range(map_bounds.position.x, map_bounds.position.x + map_bounds.size.x + 1):
			var sx := Vector2(x * cell_size, map_bounds.position.y * cell_size)
			var ex := Vector2(x * cell_size, (map_bounds.position.y + map_bounds.size.y) * cell_size)
			draw_line(sx, ex, Color(1, 1, 1, 0.25), 1.0)
		for y in range(map_bounds.position.y, map_bounds.position.y + map_bounds.size.y + 1):
			var sy := Vector2(map_bounds.position.x * cell_size, y * cell_size)
			var ey := Vector2((map_bounds.position.x + map_bounds.size.x) * cell_size, y * cell_size)
			draw_line(sy, ey, Color(1, 1, 1, 0.25), 1.0)
```

- [ ] **Step 2: 跑 playable-ui 确认通过(或更新静态断言)**

Run: `python apr/playable-ui/oracle/run_playable_ui_oracle.py`
Expected: PASS。若 runner 静态断言要求 `_draw` 含无条件 `draw_line` —— 改断言为校验"`fenced_area_mode` 条件包住 draw_line"(网格仅建造模式)。

- [ ] **Step 3: 跑全部单测确认未回归**

Run: `powershell.exe -File tools/godot/run-tests.ps1`
Expected: `GODOT_TESTS: PASS`

- [ ] **Step 4: Commit**

```bash
git add scripts/MainGame.gd apr/playable-ui/oracle/
git commit -m "feat(p3): grass ground; grid lines only in build mode"
```

---

### Task 3.2: 非建造模式不画 drag-rect 选中框

**Files:**
- Modify: `scripts/ui/GridSelectionOverlay.gd:86-93`(`_draw` drag-rect)
- Test: 新建 `apr/playable-ui/oracle/selection_box_oracle.gd`(场景 smoke)

设计:`GridSelectionOverlay._draw` 的 drag-rect 绘制(`:86-93`)加 `if owner_fenced_area_mode` 条件。overlay 需知道当前模式 —— 加一个 `build_mode: bool` 标志,MainGame 在 `toggle_fenced_area_mode` 时同步给它。

- [ ] **Step 1: 写失败 oracle**

Create `apr/playable-ui/oracle/selection_box_oracle.gd`:
```gdscript
extends SceneTree

const PASS_MARKER := "SELECTION_BOX_ORACLE: PASS"
const FAIL_MARKER := "SELECTION_BOX_ORACLE: FAIL"

const OverlayScript := preload("res://scripts/ui/GridSelectionOverlay.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var overlay = OverlayScript.new()
	# overlay 必须有 build_mode 标志,默认 false(非建造)。
	_assert_true("build_mode" in overlay, "overlay has build_mode flag")
	_assert_true(overlay.build_mode == false, "build_mode defaults to false")


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/playable-ui/oracle/selection_box_oracle.gd`
Expected: FAIL —— `build_mode` 不存在。

- [ ] **Step 3: 实现 build_mode 标志 + drag-rect 条件**

`scripts/ui/GridSelectionOverlay.gd`:加成员 `var build_mode: bool = false`。`_draw`(`:86-93`)的 drag-rect 绘制外层包 `if build_mode:`。

`scripts/MainGame.gd.toggle_fenced_area_mode`(`:221-224`)同步:
```gdscript
func toggle_fenced_area_mode() -> void:
	fenced_area_mode = not fenced_area_mode
	grid_selection_overlay.enabled = true
	grid_selection_overlay.build_mode = fenced_area_mode
	grid_selection_overlay.queue_redraw()
	_update_feedback_text("FencedArea mode %s" % ("on" if fenced_area_mode else "off"))
```

- [ ] **Step 4: 跑 oracle + 单测确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/playable-ui/oracle/selection_box_oracle.gd` → `SELECTION_BOX_ORACLE: PASS`
Run: `powershell.exe -File tools/godot/run-tests.ps1` → `GODOT_TESTS: PASS`

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/GridSelectionOverlay.gd scripts/MainGame.gd apr/playable-ui/oracle/selection_box_oracle.gd
git commit -m "feat(p3): drag-rect selection box only in build mode"
```

---

### Task 3.3: 滚轮 zoom(以鼠标为锚)

**Files:**
- Modify: `scripts/MainGame.gd:96-108`(_unhandled_input 加滚轮)
- Test: 新建 `apr/camera-zoom/oracle/camera_zoom_oracle.gd`

设计:`MOUSE_BUTTON_WHEEL_UP/DOWN` 改 `camera.zoom`(乘 1.1 / 0.9),clamp 到 `[0.5, 3.0]`。锚点:缩放后调整 `camera.position` 使鼠标指向的 world 点保持不动(标准 zoom-to-cursor)。

- [ ] **Step 1: 写失败 oracle**

Create `apr/camera-zoom/oracle/camera_zoom_oracle.gd`:
```gdscript
extends SceneTree

const PASS_MARKER := "CAMERA_ZOOM_ORACLE: PASS"
const FAIL_MARKER := "CAMERA_ZOOM_ORACLE: FAIL"

const MainGameScript := preload("res://scripts/MainGame.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	await _async()


func _async() -> void:
	await process_frame
	_finish()


func _run() -> void:
	var main = MainGameScript.new()
	get_root().add_child(main)
	_assert_true(main.has_method("apply_zoom"), "MainGame has apply_zoom")


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

> 注:用 `await process_frame` 让 MainGame `_ready` 跑完再断言(参照 npc_execution_loop_oracle 的 `MainGameScript.new()` + await 模式)。

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/camera-zoom/oracle/camera_zoom_oracle.gd`
Expected: FAIL —— `apply_zoom` 不存在。

- [ ] **Step 3: 实现滚轮 zoom**

`scripts/MainGame.gd`:加成员 `const ZOOM_MIN := 0.5`、`const ZOOM_MAX := 3.0`、`const ZOOM_STEP := 1.1`。

`_unhandled_input`(`:96`)加滚轮分支:
```gdscript
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			apply_zoom(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			apply_zoom(1.0 / ZOOM_STEP)
```
```gdscript
func apply_zoom(factor: float) -> void:
	if camera == null:
		return
	var before: Vector2 = camera.zoom
	var target: float = clamp(before.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(target, target)
```

> 锚点(zoom-to-cursor)的 position 修正在交互体验上重要,但需要 viewport 鼠标坐标;最小实现先做纯 zoom(满足第 5 项"滚轮缩放"),锚点修正作为同 task 增量:若 `world_map != null`,缩放前后用 `world_map.get_local_mouse_position()` 差值修正 `camera.position`。本步先做纯 zoom 通过 oracle,锚点修正在 Step 4 加。

- [ ] **Step 4: 加 zoom-to-cursor 锚点修正**

`apply_zoom` 改为:
```gdscript
func apply_zoom(factor: float) -> void:
	if camera == null or world_map == null:
		return
	var mouse_world_before: Vector2 = world_map.get_local_mouse_position()
	var before: float = camera.zoom.x
	var target: float = clamp(before * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(target, target)
	var mouse_world_after: Vector2 = world_map.get_local_mouse_position()
	camera.position += mouse_world_before - mouse_world_after
```

- [ ] **Step 5: 跑 oracle + 单测确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/camera-zoom/oracle/camera_zoom_oracle.gd` → `CAMERA_ZOOM_ORACLE: PASS`
Run: `powershell.exe -File tools/godot/run-tests.ps1` → `GODOT_TESTS: PASS`

- [ ] **Step 6: Commit**

```bash
git add scripts/MainGame.gd apr/camera-zoom/oracle/camera_zoom_oracle.gd
git commit -m "feat(p3): mouse-wheel zoom anchored to cursor"
```

---

### Task 3.4: 控制 UI 折叠提示(角落一行,H 展开)

**Files:**
- Modify: `scenes/main.tscn`(UI 下加 ControlsHint Label)
- Modify: `scripts/MainGame.gd`(`_unhandled_input` 加 KEY_H toggle;`_wire_ui_nodes` 接 hint)
- Test: `apr/playable-ui/oracle/playable_ui_oracle.gd`(加 `UI/ControlsHint` 节点断言)

设计:UI 下加 `ControlsHint`(Label),默认显示一行 "[H] 控制说明";按 H 展开/收起完整按键表(WASD 移动镜头 / F 建造 / 滚轮缩放 / 左键选中拖拽 / 右键丢弃 / Ctrl+S 存 / Ctrl+L 读)。

- [ ] **Step 1: 加节点断言(失败测试)**

`apr/playable-ui/oracle/playable_ui_oracle.gd`:加 `_assert_has_node(scene_root, "UI/ControlsHint", failures)`。

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `python apr/playable-ui/oracle/run_playable_ui_oracle.py`
Expected: FAIL(缺 `UI/ControlsHint`)。

- [ ] **Step 3: 场景加 ControlsHint 节点**

`scenes/main.tscn` UI 下(FeedbackLabel 后,`:48` 之后)加:
```
[node name="ControlsHint" type="Label" parent="UI"]
offset_left = 16.0
offset_top = 540.0
offset_right = 520.0
offset_bottom = 700.0
text = "[H] 控制说明"
```

- [ ] **Step 4: MainGame 接 H toggle**

`scripts/MainGame.gd`:加成员 `var controls_hint: Label`、`var _controls_expanded: bool = false`、`const CONTROLS_FULL := "[H] 收起\nWASD 移动镜头\nF 建造模式\n滚轮 缩放\n左键 选中/拖拽\n右键 丢弃手持物\nCtrl+S 保存 / Ctrl+L 读取"`。

`_unhandled_input` 键盘分支(`:99`)加:
```gdscript
			elif event.keycode == KEY_H:
				toggle_controls_hint()
```
```gdscript
func toggle_controls_hint() -> void:
	_controls_expanded = not _controls_expanded
	if controls_hint != null:
		controls_hint.text = CONTROLS_FULL if _controls_expanded else "[H] 控制说明"
```

`_wire_ui_nodes`(`:510`)末尾加:
```gdscript
	controls_hint = ui_layer.get_node_or_null("ControlsHint")
```

- [ ] **Step 5: 跑 oracle + 单测确认通过**

Run: `python apr/playable-ui/oracle/run_playable_ui_oracle.py` → PASS
Run: `powershell.exe -File tools/godot/run-tests.ps1` → `GODOT_TESTS: PASS`

- [ ] **Step 6: Commit**

```bash
git add scenes/main.tscn scripts/MainGame.gd apr/playable-ui/oracle/playable_ui_oracle.gd
git commit -m "feat(p3): collapsible controls hint (H to expand)"
```

---

### Task 3.5: 日程侧栏(选中 NPC 显示 todo_list)

**Files:**
- Create: `scripts/ui/ScheduleSidebar.gd`
- Modify: `scenes/main.tscn`(UI 下加 ScheduleSidebar)
- Modify: `scripts/MainGame.gd`(选中变化时刷新侧栏)
- Test: 新建 `apr/schedule-sidebar/oracle/schedule_sidebar_oracle.gd`

设计:`ScheduleSidebar`(PanelContainer + VBoxContainer)方法 `show_for_npc(npc)`:清空后逐条渲染 todo_list,前缀 ✓(done)/▶(active)/·(pending)/✗(BLOCKED)。`clear()` 隐藏。MainGame 选中 NPC 后调 `show_for_npc`,选中非 NPC/取消时 `clear`。

- [ ] **Step 1: 写失败 oracle**

Create `apr/schedule-sidebar/oracle/schedule_sidebar_oracle.gd`:
```gdscript
extends SceneTree

const PASS_MARKER := "SCHEDULE_SIDEBAR_ORACLE: PASS"
const FAIL_MARKER := "SCHEDULE_SIDEBAR_ORACLE: FAIL"

const SidebarScript := preload("res://scripts/ui/ScheduleSidebar.gd")
const NPCStateScript := preload("res://scripts/state/NPCState.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var sidebar = SidebarScript.new()
	get_root().add_child(sidebar)
	var npc = NPCStateScript.from_dict({"id": "npc_a", "display_name": "Jiu", "position": {"x": 16.0, "y": 16.0}})
	npc.todo_list = [
		TodoItemScript.from_dict({"id": "t1", "intent": "rest", "reason": "歇会儿", "status": "done"}),
		TodoItemScript.from_dict({"id": "t2", "intent": "wander", "reason": "逛逛", "status": "active"}),
		TodoItemScript.from_dict({"id": "t3", "intent": "visit_place", "reason": "回家", "status": "pending"}),
	]
	sidebar.show_for_npc(npc)
	var lines = sidebar.get_rendered_lines()
	_assert_true(lines.size() == 3, "renders 3 todo lines, got %d" % lines.size())
	_assert_true(lines[0].begins_with("✓"), "done prefixed ✓: %s" % lines[0])
	_assert_true(lines[1].begins_with("▶"), "active prefixed ▶: %s" % lines[1])
	_assert_true(lines[2].begins_with("·"), "pending prefixed ·: %s" % lines[2])
	sidebar.clear()
	_assert_true(sidebar.get_rendered_lines().is_empty(), "clear empties sidebar")


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/schedule-sidebar/oracle/schedule_sidebar_oracle.gd`
Expected: FAIL —— `ScheduleSidebar.gd` 不存在。

- [ ] **Step 3: 实现 ScheduleSidebar**

Create `scripts/ui/ScheduleSidebar.gd`:
```gdscript
extends PanelContainer
class_name ScheduleSidebar

var _vbox: VBoxContainer
var _lines: Array = []


func _ready() -> void:
	if _vbox == null:
		_vbox = VBoxContainer.new()
		_vbox.name = "VBox"
		add_child(_vbox)
	visible = false


func _ensure_vbox() -> void:
	if _vbox == null:
		_vbox = VBoxContainer.new()
		_vbox.name = "VBox"
		add_child(_vbox)


func show_for_npc(npc) -> void:
	_ensure_vbox()
	clear()
	if npc == null or not (npc.todo_list is Array):
		return
	visible = true
	for todo in npc.todo_list:
		var prefix := _status_prefix(StringName(todo.status))
		var line := prefix + " " + str(todo.intent) + " — " + str(todo.reason)
		var label := Label.new()
		label.text = line
		_vbox.add_child(label)
		_lines.append(line)


func clear() -> void:
	_ensure_vbox()
	for child in _vbox.get_children():
		child.queue_free()
	_lines = []
	visible = false


func get_rendered_lines() -> Array:
	return _lines.duplicate()


func _status_prefix(status: StringName) -> String:
	if status == &"done":
		return "✓"
	if status == &"active":
		return "▶"
	if status == &"BLOCKED":
		return "✗"
	return "·"
```

- [ ] **Step 4: 场景加 ScheduleSidebar + MainGame 接线**

`scenes/main.tscn` UI 下加:
```
[node name="ScheduleSidebar" type="PanelContainer" parent="UI"]
offset_left = 600.0
offset_top = 16.0
offset_right = 900.0
offset_bottom = 400.0
script = ExtResource("6_schedule_sidebar")
```
ext_resource 区加:
```
[ext_resource type="Script" path="res://scripts/ui/ScheduleSidebar.gd" id="6_schedule_sidebar"]
```

`scripts/MainGame.gd`:加成员 `var schedule_sidebar`;`_wire_ui_nodes` 末尾加 `schedule_sidebar = ui_layer.get_node_or_null("ScheduleSidebar")`。在 `select_cell_target` 选中 NPC 后刷新侧栏,选中非 NPC/取消时 clear:
在 `select_cell_target` 命中 NPC 分支(设 highlight 后)加:
```gdscript
		if schedule_sidebar != null and entity_registry.npcs.has(hit_id):
			schedule_sidebar.show_for_npc(entity_registry.npcs[hit_id])
		elif schedule_sidebar != null:
			schedule_sidebar.clear()
```
在未命中分支(`selected_entity_id = &""` 后)加 `if schedule_sidebar != null: schedule_sidebar.clear()`。

- [ ] **Step 5: 跑 oracle + playable-ui + 单测**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/schedule-sidebar/oracle/schedule_sidebar_oracle.gd` → PASS
Run: `python apr/playable-ui/oracle/run_playable_ui_oracle.py` → PASS(如需,加 `UI/ScheduleSidebar` 节点断言)
Run: `powershell.exe -File tools/godot/run-tests.ps1` → PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/ScheduleSidebar.gd scenes/main.tscn scripts/MainGame.gd apr/schedule-sidebar/oracle/
git commit -m "feat(p3): schedule sidebar shows selected NPC todo_list with status glyphs"
```

---

### Task 3.6: 气泡内容接线(todo.reason + 事件反馈)

**Files:**
- Modify: `scripts/MainGame.gd`(`_decide_one_npc` 已在 P1 Task 1.4 接了 `show_bubble(reason)`;此处补事件反馈接线 + 验证)
- Test: 新建 `apr/speech-bubble/oracle/speech_bubble_oracle.gd`

设计:P1 Task 1.4 已在发起 todo 时 `show_bubble(str(todo.reason))`。本 task 补:`update_feedback_reaction`(`:250`)被反馈系统调用时,若有 selected/相关 NPC,也把反应文本喂其气泡。并加 oracle 锁定"发起 todo → 对应 NPCVisual 气泡显示 reason"。

- [ ] **Step 1: 写失败 oracle**

Create `apr/speech-bubble/oracle/speech_bubble_oracle.gd`:
```gdscript
extends SceneTree

const PASS_MARKER := "SPEECH_BUBBLE_ORACLE: PASS"
const FAIL_MARKER := "SPEECH_BUBBLE_ORACLE: FAIL"

const MainGameScript := preload("res://scripts/MainGame.gd")
const TodoItemScript := preload("res://scripts/state/TodoItem.gd")

var failures: Array = []
var main = null


func _initialize() -> void:
	main = MainGameScript.new()
	get_root().add_child(main)
	_async()


func _async() -> void:
	await process_frame
	_run()
	_finish()


func _run() -> void:
	# 取 seed NPC,给一个带 reason 的 pending todo,tick 决策后气泡应显示 reason。
	var npc = null
	for n in main.entity_registry.npcs.values():
		npc = n
		break
	_assert_true(npc != null, "seed npc exists")
	if npc == null:
		return
	npc.todo_list = [TodoItemScript.from_dict({"id": "tb", "intent": "wander", "reason": "去看看那罐可乐", "status": "pending"})]
	main.tick_npc_execution()
	var visual = main.entity_visual_layer.npc_visuals.get(npc.id)
	_assert_true(visual != null, "npc visual exists")
	if visual == null:
		return
	var bubble = visual.get_node_or_null("SpeechBubble")
	_assert_true(bubble != null and bubble.visible, "bubble visible after decide")
	_assert_true(bubble != null and bubble.text == "去看看那罐可乐", "bubble shows todo reason, got: %s" % (bubble.text if bubble != null else "<none>"))


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

- [ ] **Step 2: 跑 oracle**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/speech-bubble/oracle/speech_bubble_oracle.gd`
Expected: 若 P1 Task 1.4 的 `show_bubble` 接线正确,应直接 PASS;若 FAIL(如 visual 尚未 sync),在 `tick_npc_execution` 前先 `main.entity_visual_layer.sync_from_registry(main.entity_registry)` —— 但更稳妥是让 `_decide_one_npc` 在 show_bubble 前确保 visual 存在:在 Step 3 修。

- [ ] **Step 3: 确保 decide 时 visual 已存在 + 补事件反馈接线**

`scripts/MainGame.gd._decide_one_npc`:在 `show_bubble` 前确保 sync:
```gdscript
	if entity_visual_layer != null:
		entity_visual_layer.sync_from_registry(entity_registry)
		if entity_visual_layer.npc_visuals.has(npc.id):
			entity_visual_layer.npc_visuals[npc.id].show_bubble(str(todo.reason))
```

`update_feedback_reaction`(`:250`)补:若有 selected NPC,喂其气泡:
```gdscript
func update_feedback_reaction(event_text: String) -> void:
	_update_feedback_text(event_text)
	if entity_visual_layer != null and selected_entity_id != &"" and entity_visual_layer.npc_visuals.has(selected_entity_id):
		entity_visual_layer.npc_visuals[selected_entity_id].show_bubble(event_text)
```

- [ ] **Step 4: 跑 oracle + 单测确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/speech-bubble/oracle/speech_bubble_oracle.gd` → `SPEECH_BUBBLE_ORACLE: PASS`
Run: `powershell.exe -File tools/godot/run-tests.ps1` → `GODOT_TESTS: PASS`

- [ ] **Step 5: Commit**

```bash
git add scripts/MainGame.gd apr/speech-bubble/oracle/
git commit -m "feat(p3): speech bubble shows todo reason on decide + event reaction"
```

---

### Task 3.7: GameClock 驱动自动日程(去手动 T)

**Files:**
- Create: `scripts/world/GameClock.gd`
- Modify: `scripts/MainGame.gd`(_process 驱动时钟;早上事件触发 request_daily_todos_for_all_npcs;HUD 显示 day/time)
- Modify: `scenes/main.tscn`(UI 下加 ClockLabel)
- Test: 新建 `apr/game-clock/oracle/game_clock_oracle.gd`

设计:`GameClock`:`advance(delta)` 累加;`SECONDS_PER_DAY` 现实秒=一游戏天;每天到"早上"时间点(day 起始)触发一次 `morning` 回调(用一个 `consume_morning_event() -> bool` 边沿检测,避免重复触发)。暴露 `day: int`、`time_of_day: float`(0..1)。MainGame `_process` 调 `clock.advance(delta)`,若 `consume_morning_event()` 为 true 则 `request_daily_todos_for_all_npcs()`。HUD ClockLabel 显示 `Day N · HH:MM`。

- [ ] **Step 1: 写失败 oracle**

Create `apr/game-clock/oracle/game_clock_oracle.gd`:
```gdscript
extends SceneTree

const PASS_MARKER := "GAME_CLOCK_ORACLE: PASS"
const FAIL_MARKER := "GAME_CLOCK_ORACLE: FAIL"

const GameClockScript := preload("res://scripts/world/GameClock.gd")

var failures: Array = []


func _initialize() -> void:
	_run()
	_finish()


func _run() -> void:
	var clock = GameClockScript.new()
	# 第 0 帧:第一个早上事件应可被消费一次。
	clock.advance(0.0)
	_assert_true(clock.consume_morning_event(), "first morning event fires")
	_assert_true(not clock.consume_morning_event(), "morning event consumed once (edge-triggered)")
	_assert_true(clock.day == 1, "starts at day 1, got %d" % clock.day)
	# 推进一整天:进入第 2 天,新早上事件。
	clock.advance(clock.SECONDS_PER_DAY)
	_assert_true(clock.day == 2, "advances to day 2, got %d" % clock.day)
	_assert_true(clock.consume_morning_event(), "morning event fires on new day")
	# time_of_day 在 [0,1)。
	_assert_true(clock.time_of_day >= 0.0 and clock.time_of_day < 1.0, "time_of_day in [0,1), got %.2f" % clock.time_of_day)


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _finish() -> void:
	if failures.is_empty():
		print(PASS_MARKER)
		quit(0)
	else:
		print(FAIL_MARKER)
		for f in failures:
			print("  - %s" % f)
		quit(1)
```

- [ ] **Step 2: 跑 oracle 确认失败**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/game-clock/oracle/game_clock_oracle.gd`
Expected: FAIL —— `GameClock.gd` 不存在。

- [ ] **Step 3: 实现 GameClock**

Create `scripts/world/GameClock.gd`:
```gdscript
extends RefCounted
class_name GameClock

const SECONDS_PER_DAY := 120.0   # 2 分钟现实时间 = 一游戏天
const MORNING_THRESHOLD := 0.0    # 一天起点即"早上"

var day: int = 1
var time_of_day: float = 0.0      # 0..1
var _elapsed: float = 0.0
var _morning_pending: bool = true # 启动即有一个早上事件待消费
var _last_day_for_morning: int = 0


func advance(delta: float) -> void:
	_elapsed += delta
	var new_day: int = 1 + int(_elapsed / SECONDS_PER_DAY)
	time_of_day = fmod(_elapsed, SECONDS_PER_DAY) / SECONDS_PER_DAY
	if new_day != day:
		day = new_day
		_morning_pending = true


func consume_morning_event() -> bool:
	if _morning_pending and _last_day_for_morning != day:
		_morning_pending = false
		_last_day_for_morning = day
		return true
	# 启动首日特例:_last_day_for_morning 初始 0 != day(1) 时第一次也命中上面分支。
	return false


func time_label() -> String:
	var minutes_total: int = int(time_of_day * 24.0 * 60.0)
	var hh: int = minutes_total / 60
	var mm: int = minutes_total % 60
	return "Day %d · %02d:%02d" % [day, hh, mm]
```

> 边沿检测说明:`_last_day_for_morning` 初始 0,首次 `consume` 时 day=1≠0 → 触发并记 1;同 day 再 consume 时 1==1 → 不触发。新 day(advance 设 `_morning_pending=true`)后 `_last_day_for_morning`(旧 day)≠ 新 day → 再触发。满足 oracle 的边沿语义。

- [ ] **Step 4: 跑 oracle 确认通过**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/game-clock/oracle/game_clock_oracle.gd`
Expected: `GAME_CLOCK_ORACLE: PASS`。若首日边沿不符,微调 `consume_morning_event`(确保首次必触发、同日不重复、新日再触发)。

- [ ] **Step 5: MainGame 接时钟 + HUD + 去手动 T 依赖**

`scripts/MainGame.gd`:加成员 `var game_clock`、`var clock_label: Label`。`_wire_core_world_services` 末尾 `game_clock = GameClockScript.new()`(加 preload `const GameClockScript := preload("res://scripts/world/GameClock.gd")`)。

`_process`(`:85`)加:
```gdscript
	if game_clock != null:
		game_clock.advance(delta)
		if game_clock.consume_morning_event():
			request_daily_todos_for_all_npcs()
		if clock_label != null:
			clock_label.text = game_clock.time_label()
```

`_wire_ui_nodes` 加 `clock_label = ui_layer.get_node_or_null("ClockLabel")`。

`scenes/main.tscn` UI 下加:
```
[node name="ClockLabel" type="Label" parent="UI"]
offset_left = 600.0
offset_top = 0.0
offset_right = 900.0
offset_bottom = 16.0
text = "Day 1 · 00:00"
```

**T 键保留为调试手动触发**(`:102-103` 的 `KEY_T` → `generate_daily_todo_hotkey_placeholder` 不变),但不再是唯一入口。铁律 1:触发器多了时钟,管线不变。

- [ ] **Step 6: 跑 oracle + 单测 + playable-ui + llm_live(无 key 应 SKIP)**

Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/game-clock/oracle/game_clock_oracle.gd` → PASS
Run: `powershell.exe -File tools/godot/run-tests.ps1` → `GODOT_TESTS: PASS`
Run: `python apr/playable-ui/oracle/run_playable_ui_oracle.py` → PASS
Run: `powershell.exe -File tools/godot/godot.ps1 --headless --script apr/npc-loop/oracle/llm_live_oracle.gd` → `LLM_LIVE_ORACLE: SKIP`(无 .env key)或 PASS(有 key)。验证铁律 1:request_daily_todos 管线未变。

- [ ] **Step 7: Commit**

```bash
git add scripts/world/GameClock.gd scripts/MainGame.gd scenes/main.tscn apr/game-clock/oracle/
git commit -m "feat(p3): GameClock drives auto daily planning (morning event); T remains debug trigger; HUD clock"
```

---

**P3 完成验收:** 草地地面 + 网格仅建造模式;非建造模式无 drag-rect;滚轮 zoom 锚定光标;控制提示折叠(H);日程侧栏显示选中 NPC 的 todo;头顶气泡显示 todo reason + 事件反应;时钟自动触发每日规划(T 保留调试)。全部 oracle + 单测 + verify_project 绿,llm_live 按 key 状态 SKIP/PASS。

---

## 最终验收清单(全计划完成后)

逐条对照 spec 的 10 项需求 + 两条铁律:

| # | 需求 | 由哪个 Task 兑现 | 验证 |
|---|---|---|---|
| 1 | NPC/物品不绑格,格子仅建造模式显示 | P0.2/P1.2 连续 position + P3.1/P3.2 网格条件 | 视觉 + entity_visual/continuous_move oracle |
| 2 | 草地 | P3.1 | 目视 + playable-ui |
| 3 | 连续平滑移动 | P1.2/P1.4 | continuous_move + npc_execution_loop oracle |
| 4 | 物品在手显示 | P0.3 HeldItemAnchor + P2.4 Step 6.5 reparent | entity_visual oracle(持有 reparent 断言) |
| 5 | 滚轮 zoom | P3.3 | camera_zoom oracle |
| 6 | 控制 UI | P3.4 | playable-ui 节点断言 |
| 7 | 非建造模式无选中框 | P3.2 | selection_box oracle |
| 8 | 自动日程 + 侧栏 | P3.7 时钟 + P3.5 侧栏 | game_clock + schedule_sidebar oracle |
| 9 | 头顶气泡 | P0.4 容器 + P3.6 内容 | speech_bubble oracle |
| 10 | 拖拽重力感 | P2.4 | drag_gravity oracle |
| 铁律1 | AI Town 边界 | P3.7(只改触发,管线不变) | llm_live oracle |
| 铁律2 | 回归门 | 全程 pre→post 更新 | 全 oracle + 单测 + verify_project |

**新增 oracle 清单(本计划引入,均需 fix 前红/fix 后绿):** entity_visual、continuous_move(+set_position)、intent_resolve、drag_gravity、selection_box、camera_zoom、schedule_sidebar、speech_bubble、game_clock。**重写的既有 oracle:** npc_execution_loop(逐帧到达)、npc_loop(真不可达 BLOCKED)、test_core_behaviors(删同格去重/rebuild、改 occupancy 断言为 position)、verify_project(字段/方法表)、playable_ui(新节点 + 选中/绘制静态断言)。**保持不变:** place_registry_walkable、llm_live(铁律 1)。

