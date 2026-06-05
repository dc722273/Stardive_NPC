# AI-native NPC Emergence Sandbox Core Design

日期: 2026-06-04

## 目标

做一个 Godot 首版玩法原型: 玩家在网格地图上观察和干预 NPC 日常生活, 通过拖拽 NPC / 物品、给 NPC 物品、右键让 NPC 丢弃物品、以及在游玩中划定地点, 影响 NPC 的对话、反馈和每日行为计划。

核心不是传统任务系统, 而是 **AI-native world fact authoring**: 玩家在游戏中创造可被 NPC 理解的事实, NPC 每天根据这些事实生成自己的 todo list, 并在玩家干预时即时反馈。

## 技术基线

- Engine: Godot 4.6.x stable 起步。
- 首版脚本: GDScript 优先, 降低原型成本。
- 地图: grid-based map, 使用 Godot grid / TileMapLayer 坐标作为玩法坐标。
- AI: LLM 负责生成 NPC daily todo list 和自然语言反馈, Godot runtime 负责结构化校验、可达性检查和 fallback。
- 美术: MVP 阶段只使用 Godot 基础图形组合、emoji、文本标签和半透明 overlay。emoji 是临时 display layer, 不是正式美术方向, 也不能作为 gameplay source of truth。

## 玩家基础操作

| 操作 | 输入 | 结果 |
| --- | --- | --- |
| 摄像机移动 | `WASD`, 或鼠标移动到屏幕边缘 | 摄像机平移 |
| 物件 / 人物选择 | 鼠标左键点击 | 选中 NPC 或物品 |
| 物件 / 人物拖动 | 选中后按住鼠标左键并移动 | 被选中实体跟随鼠标 |
| 放置物件 / 人物 | 松开鼠标左键 | 根据 drop 位置触发放置或交互 |
| 人物拾取物件 | 鼠标左键拖动物品到 NPC 身上并松开 | NPC 持有物品并反馈 |
| 人物丢弃物件 | 鼠标右键点击携带物品的 NPC | NPC 将持有物品丢到脚边并反馈 |
| 地图地点编辑 | 打开 FencedArea 创建模式, 鼠标拖拽网格矩形 | 创建带围栏语义的地点 |
| 建筑放置 | 在网格上选择建筑目标 cell | 通过 occupancy / path impact 检查后放置 |

## 核心实体

### NPC

NPC 是有身份、关系、记忆和每日计划的角色。首版 NPC 至少包含:

```gdscript
NPCState {
  id: StringName
  display_name: String
  personality: String
  current_cell: Vector2i
  held_item_id: StringName # empty = no held item
  todo_list: Array[TodoItem]
  recent_events: Array[InteractionEvent]
}
```

约束:

- 每个 NPC 首版只能持有一个物品。
- `held_item_id` 为空表示没有持有物品。
- NPC 的行为系统不直接读 UI, 只读 world state / registry / event log。

### Item

物品是可拖拽、可放置、可被 NPC 持有的世界对象。

```gdscript
ItemState {
  id: StringName
  display_name: String
  description: String
  current_cell: Vector2i # INVALID_CELL when held
  held_by_npc_id: StringName # empty = on grid
}
```

持有 / grid occupancy 约束:

- `held_by_npc_id` 为空时, 物品在 grid 上, `current_cell` 必须是有效 cell, 并占用 item occupancy。
- `held_by_npc_id` 非空时, 物品不占用 grid cell, `current_cell` 必须设为 `INVALID_CELL`, 视觉上挂到持有 NPC。
- `npc.held_item_id` 和 `item.held_by_npc_id` 是双向 invariant, 必须由 `WorldEntityRegistry` 事务式更新。
- Save/load 时先恢复 NPC / item 原始状态, 再校验双向关系; 如果一端缺失, 以 NPC inventory 为准并记录 repair warning。

`INVALID_CELL` 是 `WorldEntityRegistry` 定义的命名 sentinel, 不能落在合法地图范围内, 只用于表示“当前不在 grid 上”。

### Place

Place 是玩家在地图上创建的地点 world fact。它不是纯 UI overlay, 而是 NPC 可查询、可用于 todo planning 的结构化事实。

MVP 只有一种可持久化 Place: `FencedAreaPlace`。不要同时持久化一份 `Place` 和一份 `FencedArea`; `FencedAreaPlace.id` 是地点、围栏、建筑语义共享的唯一 id。

```gdscript
FencedAreaPlace {
  id: StringName
  name: String
  description: String
  created_by: StringName # "player"
  updated_at_tick: int
  emoji: String
  footprint: Rect2i
  door_cell: Vector2i
  fence_cells: Array[Vector2i]
  interior_cells: Array[Vector2i]
}
```

`footprint` 是地点范围的唯一 rectangle source of truth。不要再保存重复的 `rect_cells`; 查询 Place 命中时使用 `footprint`。

当前不做普通 Place 创建工具。也就是说, FencedArea 不是 Place 之外的另一套世界概念, 而是带有围栏寻路语义的 Place。玩家看到的是鼠标拖拽框选, runtime 保存的是 grid data, 不保存像素坐标。

## 玩家拖拽与 Drop 交互

拖拽过程只做 preview / hover highlight, 不触发 NPC 反馈。所有正式交互在 **松开鼠标左键** 时触发。

### Drop 规则

1. Drop 到空网格:
   - 先由 `WorldEntityRegistry.validate_forced_drop(entity_id, target_cell)` 校验目标 cell。
   - 目标 cell 必须在地图内、walkable、未被占用, 且不能是 `fence_cell` 或其他 blocked cell。
   - NPC 或物品被放到目标 cell。
   - 玩家拖拽 NPC 是 forced relocation, 可以把 NPC 直接放入 FencedArea interior; 这不代表 NPC autonomous movement 可以穿墙。
   - NPC 后续自主进出 FencedArea 仍必须通过 `door_cell`。
   - 不触发特殊 NPC 反馈, 除非目标 cell 属于特殊 Place。

2. Drop 物品到 NPC 身上:
   - 如果 NPC 没有持有物品, NPC 接收物品。
   - 操作作为一个 inventory transaction 执行。
   - 设置 `item.held_by_npc_id = npc.id`。
   - 设置 `item.current_cell = INVALID_CELL`, 并从 grid item occupancy 移除。
   - 设置 `npc.held_item_id = item.id`。
   - 触发 NPC feedback。

3. Drop 物品到已持有物品的 NPC 身上:
   - 首版不允许替换。
   - 物品回到 drop 前位置或落到 NPC 附近空 cell。
   - 如果找不到附近空 cell, 回滚到 drag start snapshot, 不改变 `held_by_npc_id / current_cell / held_item_id`。
   - NPC 反馈拒绝原因。

4. Drop NPC 到物品旁边:
   - NPC 不自动拾取, 除非 drop target 被判定为物品。
   - 可触发 NPC 对附近物品的反馈。

5. Drop NPC 到 NPC 旁边:
   - 触发 encounter feedback。
   - 可用于纸面推演中的“川普撞见九筒”“师爷撞见九筒”。

### 右键丢弃

玩家右键点击携带物品的 NPC:

1. runtime 找到 NPC 当前 cell 周围最近可放置 cell。
2. 将 held item 放到该 cell。
3. 清空 `npc.held_item_id` 和 `item.held_by_npc_id`。
4. 设置 `item.current_cell` 为落点 cell, 并重新加入 grid item occupancy。
5. 记录 `player_forced_drop_item` 事件。
6. NPC 可生成一句反馈。

如果找不到可放置 cell, 丢弃失败, 持有状态保持不变, NPC 反馈失败原因。

## Interaction Event

玩家干预和 NPC 遭遇统一记录为事件, 供反馈、记忆和 LLM context 使用。

```gdscript
InteractionEvent {
  id: StringName
  type: StringName
  actor_id: StringName # usually "player"
  primary_entity_id: StringName
  target_entity_id: StringName
  target_type: StringName # "npc" | "item" | "place" | "cell"
  cell: Vector2i
  tick: int
  payload: Dictionary
}
```

首版事件类型:

- `player_drop_item_on_npc`
- `player_drop_item_on_cell`
- `player_drop_npc_on_cell`
- `player_drop_npc_near_item`
- `player_drop_npc_near_npc`
- `player_forced_drop_item`
- `npc_entered_place`
- `npc_visited_place`
- `npc_talked_to_npc`
- `npc_inspected_item`
- `player_placed_building`
- `npc_todo_blocked_by_building`
- `llm_request_cancelled`
- `npc_action_interrupted`

`payload` 是 typed dictionary, 只保存该事件类型需要的额外结构化字段:

- `player_placed_building`: `place_id`, `footprint`, `door_cell`, `fence_cells`, `interior_cells`
- `npc_todo_blocked_by_building`: `npc_id`, `todo_id`, `place_id`, `blocked_cell`, `failure_reason`
- `llm_request_cancelled`: `operation_id`, `npc_id`, `kind`, `generation`, `reason`
- `npc_action_interrupted`: `action_id`, `todo_id`, `lane`, `interrupt_policy`, `reason`
- `npc_visited_place`: `npc_id`, `todo_id`, `place_id`
- `npc_talked_to_npc`: `npc_id`, `todo_id`, `target_npc_id`
- `npc_inspected_item`: `npc_id`, `todo_id`, `item_id`

## NPC 反馈

NPC feedback 在事件发生后生成。输入 context 控制在小范围内:

```text
NPC identity/personality
current place name + description
held item
event type
dragged/dropped entity
nearby NPC / item
recent relevant events
relationships
```

示例纸面推演:

- 可乐拿给九筒:
  - 九筒: "这是什么玩意儿? 能喝的? 我现在不渴, 小六可能爱喝。"
- 可乐拿给师爷:
  - 师爷: "谁干的啊, 在鹅城这玩意儿太烫手, 随时要了我的老命!"
- 川普撞见九筒:
  - 川普: "你为什么会有这个东西? 在鹅城这是我才能享用的。"
- 师爷撞见九筒:
  - 师爷: "哎哟, 你怎么会有这个玩意儿, 还不快藏起来, 万一被老爷看见了就不得了了!"

## 地图地点编辑

地图编辑是游玩中随时可用的轻量 overlay, 不是独立 editor。

流程:

1. 玩家打开 FencedArea 创建模式。
2. 鼠标左键在网格上按下。
3. 拖拽出矩形 cell range。
4. 松开后弹出 `FencedAreaEditPanel`。
5. 玩家填写:
   - `name`: 自定义地点名, 例如“鹅城医院”“川普专属餐厅”
   - `description`: 简短世界描述, 给 NPC / LLM 使用
6. 确认后创建 `FencedAreaPlace` 并显示在地图上。

首版不要求玩家选择固定类型。医院 / 学校 / 餐厅只是示例, 玩家可以创建任意地点名。当前所有玩家创建的地点都必须是 FencedArea Place。

## Building/FencedArea 放置与路径阻塞

建筑当前阶段不是复杂美术资产, 而是一片长方形 `Building/FencedArea`。MVP 视觉上显示为建筑 emoji + 矩形区域 + 名字, 但寻路语义按围栏处理: footprint 边界是 fence, 唯一门 cell 是缺口, 内部区域可通行。

本节的 Building/FencedArea 指 `FencedAreaPlace` 的 placement/pathfinding 侧面, 不是另一份持久化对象。`footprint / door_cell / fence_cells / interior_cells` 都保存在同一个 `FencedAreaPlace` 上。

`fence_cells` 由 footprint 边界自动计算, 但必须排除 `door_cell`。`interior_cells` 是 footprint 内部可走区域。emoji / label 只是 display layer, gameplay 语义必须来自 `FencedAreaPlace` 数据。

Building/FencedArea 放置会改变地图可通行性, 因此必须先经过 runtime invariant 检查。

### 放置规则

1. 不能让 footprint 覆盖任何 NPC 当前所在 cell。
   - 这是硬禁止, 不进入 replan。
   - 原因: 即使内部可通行, 也会产生“玩家突然把 NPC 圈进围栏”的卡死或归属语义。

2. footprint 必须有合法尺寸。
   - MVP 最小合法尺寸是 `3x3`。
   - `interior_cells` 定义为严格在 footprint 内部、且不在边界上的 cells。
   - `1xN`、`2xN`、`Nx1`、`Nx2` 都没有 interior, 必须拒绝并给出 failure reason。

3. 每个 Building/FencedArea 必须有一个 `door_cell`。
   - `door_cell` 自动选择为拖拽结束边缘最近的 footprint 边缘 cell。
   - `door_cell` 必须位于 footprint 边缘。
   - `door_cell` 不能是 corner cell, 因为 corner 没有 orthogonal interior neighbor。
   - `door_cell` 不能被其他建筑、NPC 或阻挡物占用。
   - `door_cell` 必须同时连通至少一个外部可走 cell 和一个内部可走 cell。

4. 不允许 Building/FencedArea 互相交叉。
   - 新 footprint 不能与已有 Building/FencedArea footprint 重叠。
   - 新 fence 不能覆盖已有 `door_cell`。
   - 新 `door_cell` 不能落在已有 fence 或 footprint 内。

5. 围栏边界阻挡, 门和内部可走。
   - `fence_cells` 在 pathfinding grid 中设为 blocked。
   - `door_cell` 在 pathfinding grid 中保持 walkable。
   - `interior_cells` 在 pathfinding grid 中保持 walkable。
   - NPC 不能从任意边缘穿墙进入。
   - 如果目标在内部, pathfinding 应自然经过 `door_cell`。
   - 首版不做内部房间寻路; interior 只是一个可走的围栏内部区域。

6. 可以在 NPC 未来路径上放置 Building/FencedArea。
   - 放置成功后, 受影响 NPC 必须触发 replan。
   - 未来路径指 `NPCMover` / pathfinding 当前缓存路径里的 cell。

7. 如果 replan 成功:
   - NPC 继续执行当前 todo。
   - `planned_path` 更新为新路径。

8. 如果 replan 失败:
   - 当前 todo 标记为 `BLOCKED`。
   - 记录 `npc_todo_blocked_by_building` 事件。
   - NPC 切换到下一个可执行 todo。
   - 如果没有可执行 todo, fallback 到 `wander` 或 `rest`。

### BuildingPlacementService

Building/FencedArea 放置不应直接写地图, 而应通过服务层统一处理:

```gdscript
func can_place_fenced_area(footprint: Rect2i, door_cell: Vector2i) -> BuildingPlacementCheck
func place_fenced_area(name: String, description: String, footprint: Rect2i, drag_end_cell: Vector2i, emoji: String) -> BuildingPlacementResult
func choose_door_cell_from_drag(footprint: Rect2i, drag_end_cell: Vector2i) -> Vector2i
func get_door_cell(place_id: StringName) -> Vector2i
func get_fence_cells(place_id: StringName) -> Array[Vector2i]
func get_interior_cells(place_id: StringName) -> Array[Vector2i]
func get_npcs_occupying_cells(cells: Array[Vector2i]) -> Array[StringName]
func get_npcs_with_paths_intersecting(cells: Array[Vector2i]) -> Array[StringName]
```

`choose_door_cell_from_drag` 根据 drag end 位置找 footprint 边缘最近的 non-corner boundary cell; 如果 drag end 在 footprint 内, 先投影到最近边缘。若有多个同距离候选, 选择离 drag end 方向最近且外侧可走的候选。找不到同时连通外部和 interior 的候选时返回 `INVALID_CELL`, `can_place_fenced_area` 必须拒绝。

`can_place_fenced_area` 必须先检查 footprint 尺寸和 door 合法性, 再检查 footprint 是否覆盖 NPC current occupancy, 最后检查 terrain / collision / fence / door / overlap。路径影响不是禁止条件, 而是放置后的 replan 触发条件。

`place_fenced_area` 是唯一写入口。它必须在一个事务中完成:

1. 计算 `door_cell / fence_cells / interior_cells`。
2. 执行 `can_place_fenced_area`。
3. 调用 `WorldPlaceRegistry.create_fenced_area_place` 创建唯一 `FencedAreaPlace`。
4. 更新 pathfinding grid。
5. 记录 `player_placed_building` 事件。
6. 通知 `NPCMover` / `TodoExecutor` 对受影响路径 replan。

如果第 3-6 步任一步失败, 必须回滚 registry、pathfinding grid 和事件写入。

pathfinding grid 更新必须按围栏语义处理:

```gdscript
for cell in fenced_area.fence_cells:
  astar_grid.set_point_solid(cell, true)

astar_grid.set_point_solid(fenced_area.door_cell, false)

for cell in fenced_area.interior_cells:
  astar_grid.set_point_solid(cell, false)
```

禁止把整个 `footprint` 设为 blocked; 否则 NPC 无法进入区域。

pathfinding grid 更新和 replan 通知必须在同一 tick 完成。`NPCMover` 每次 movement tick 开始前要重新检查 `planned_path` 中剩余 cell 是否仍然 walkable; 如果路径已失效, 先 replan, 不继续沿旧路径移动。

## WorldPlaceRegistry

`WorldPlaceRegistry` 是 Place 的唯一 runtime 和 persistence source of truth。

MVP 内它保存 `FencedAreaPlace`。`BuildingPlacementService` 可以写入 registry, 其他系统只通过 registry 查询, 不直接维护第二份 Building/FencedArea 状态。

职责:

1. 保存所有玩家创建的 `FencedAreaPlace`。
2. 提供 grid 查询。
3. 给 NPC context builder 提供当前地点和附近地点。
4. 负责 save/load。

接口草案:

```gdscript
func create_fenced_area_place(name: String, description: String, footprint: Rect2i, door_cell: Vector2i, fence_cells: Array[Vector2i], interior_cells: Array[Vector2i], emoji: String) -> FencedAreaPlace
func update_place_text(place_id: StringName, name: String, description: String) -> void
func remove_fenced_area_place(place_id: StringName) -> void
func get_place_at_cell(cell: Vector2i) -> FencedAreaPlace
func get_places_near_cell(cell: Vector2i, radius: int) -> Array[FencedAreaPlace]
func get_random_cell_in_place(place_id: StringName) -> Vector2i
```

NPC 不直接读取地图 UI, 只通过 registry 查询 Place。

会改变 footprint / door / fence / interior 的修改必须通过 `BuildingPlacementService`, 不能直接调用 `WorldPlaceRegistry` 文本更新接口绕过 pathfinding invariant。

`create_fenced_area_place` 和 `remove_fenced_area_place` 只给 `BuildingPlacementService` 调用。`get_random_cell_in_place` 只能返回 `door_cell` 或 `interior_cells` 中 walkable 的 cell, 不能返回 fence cell。

## LLM Daily Todo List

每天早上, 每个 NPC 由 LLM 生成当天 todo list。

输入 context:

```text
NPC identity/personality
current day/time
known places: id, name, description
relationships
held item
recent events
needs/preferences
```

LLM 输出结构化 JSON:

```json
[
  {
    "intent": "visit_place",
    "target_place_id": "place_hospital",
    "reason": "昨天听说有人受伤, 想去看看",
    "priority": 80
  },
  {
    "intent": "talk_to_npc",
    "target_npc_id": "npc_shiye",
    "reason": "想确认可乐是谁带来的",
    "priority": 60
  }
]
```

Runtime guard:

1. `intent` 必须在允许列表内。
2. `target_place_id` / `target_npc_id` 必须存在。
3. 目标必须可达。
4. todo 数量不能超过当天上限。
5. 无效项丢弃; 如果列表为空, fallback 到 `wander`。
6. 当前 todo 因地图变化无法重新寻路时, 标记为 `BLOCKED`, 然后切换到下一个可执行 todo。

首版允许的 intent:

- `visit_place`
- `talk_to_npc`
- `inspect_item`
- `wander`
- `rest`

## NPC Plan/Execute 与 LLM 接线

NPC plan / execute 参考 AI Town 的边界: LLM 和 agent logic 可以异步生成计划或文本, 但 Godot runtime 是唯一 world state truth。LLM 不直接改位置、不直接写 inventory、不直接改地图, 只能提交结构化结果或流式文本片段; runtime 校验后再转成 action。

### LLM operation model

每次 LLM 调用都作为异步 operation 管理:

```gdscript
LLMOperation {
  id: StringName
  npc_id: StringName
  kind: StringName # "daily_todo" | "feedback" | "conversation"
  status: StringName # "pending" | "streaming" | "done" | "cancelled" | "failed"
  generation: int
  cancel_token: StringName
}
```

规则:

1. `DailyTodoPlanner` 可以异步请求 LLM 生成 todo list。
2. `NPCFeedbackBuilder` 可以异步请求 LLM 生成 NPC feedback。
3. 每个 operation 带 `generation`。
4. 取消请求时记录 `llm_request_cancelled` 事件。

`generation` 规则:

- `generation` 是 per `(npc_id, kind)` 的单调递增整数, 不同 kind 互不作废。
- 每次为同一 `(npc_id, kind)` 发起新 operation 时先递增 generation, 再创建 operation。
- operation 完成时必须同时匹配 `operation_id` 和当前 generation, 否则 late response 直接丢弃。
- 玩家干预只递增受影响 kind: 例如 inventory / Place 变化会作废 `daily_todo`, speech interrupt 会作废 `feedback` 或 `conversation`。
- `cancel` 不依赖底层 HTTP/WebSocket 真取消成功; 即使 remote 继续返回 chunk, generation / operation_id check 也必须让 late result 无法 commit。

### Streaming output

系统必须支持流式输出:

1. NPC feedback / conversation 文本可以 token-by-token 或 chunk-by-chunk 显示。
2. streaming 期间 NPC 可以继续移动, 只要 speech lane 没有被打断。
3. daily todo list 可以接收 streaming chunk, 但只有最终 JSON 通过 schema validation 后才能 commit 到 `todo_list`。
4. 流式文本不能直接触发 gameplay state mutation; gameplay mutation 只能来自已验证的 action / event。
5. daily todo streaming chunk 只进入 operation-local buffer。operation cancelled / failed / generation mismatch 时丢弃整个 buffer, 不解析 partial JSON。
6. daily todo cancelled 后, 如果 NPC 当前没有可执行 todo, 立即 fallback 到 `wander` 或 `rest`; 是否重新 plan 由 `DailyTodoPlanner` 的 retry policy 决定, MVP 默认同一天最多重试一次。

### Interrupt / cancel

系统必须支持可打断:

1. 玩家拖拽 NPC、给 NPC 物品、右键丢弃、建筑阻断路径, 都可以打断当前 todo execution。
2. 被打断时, `TodoExecutor` 暂停或取消当前 action bundle。
3. 如果当前 LLM operation 仍在 streaming, 根据 policy 选择:
   - `cancel`: 立刻取消并丢弃后续 chunk。
   - `finish_speech`: 允许当前短句说完, 但不再追加新动作。
   - `ignore_late_result`: 请求不一定真的取消成功, 但 late response 会因 generation mismatch 被丢弃。
4. 被打断 action 记录 `npc_action_interrupted` 事件。

### Parallel action lanes

NPC action 支持并行 lane, 但每个 lane 有资源锁:

```gdscript
NPCAction {
  id: StringName
  npc_id: StringName
  lane: StringName # "movement" | "speech" | "manipulation" | "cognition"
  kind: StringName
  status: StringName # "queued" | "running" | "done" | "blocked" | "cancelled"
  interrupt_policy: StringName
}
```

首版 lane 规则:

1. `movement` lane: 同一 NPC 同时只能有一个移动 action。
2. `speech` lane: 同一 NPC 同时只能有一个 streaming speech action。
3. `movement` 和 `speech` 可以并行, 因此 NPC 可以一边走一边说话。
4. `manipulation` lane: 拾取、丢弃、交付物品是短事务, 必须独占 inventory state。
5. `cognition` lane: LLM planning / reflection / feedback 请求在后台运行, 结果必须经过 generation check。

### TodoExecutor

`TodoExecutor` 把高层 todo 编译成可执行 action bundle:

```text
visit_place
-> movement: move_to_place_cell
-> speech: optional self-talk / arrival feedback
-> event: npc_visited_place

talk_to_npc
-> movement: move_near_target_npc
-> speech: conversation / greeting
-> event: npc_talked_to_npc

inspect_item
-> movement: move_near_item
-> speech: reaction
-> event: npc_inspected_item
```

如果 action bundle 中任一必需 action 失败, 当前 todo 进入 `FAILED` 或 `BLOCKED`; 如果是地图阻塞导致不可达, 使用 `BLOCKED`。

## Godot 节点与模块边界

```text
GameRoot
├─ WorldMap
│  ├─ TileMapLayer
│  ├─ GridSelectionOverlay
│  └─ FencedAreaOverlay
├─ UI
│  └─ FencedAreaEditPanel
├─ WorldState
│  ├─ WorldPlaceRegistry
│  ├─ WorldEntityRegistry
│  ├─ BuildingPlacementService
│  └─ InteractionEventLog
└─ NPCSystem
   ├─ NPCController
   ├─ NPCInventory
   ├─ NPCFeedbackBuilder
   ├─ NPCMemoryContextBuilder
   ├─ LLMClient
   ├─ DailyTodoPlanner
   ├─ TodoExecutor
   ├─ NPCActionScheduler
   └─ NPCMover
```

### GridSelectionOverlay

- 处理鼠标按下、拖拽、松开。
- 将 screen / world position 转成 grid cell。
- 生成 `Rect2i`。
- 不保存 Place。

### FencedAreaEditPanel

- 编辑 `name + description`。
- 确认后调用 `BuildingPlacementService.place_fenced_area` 创建 `FencedAreaPlace`。
- 不直接影响 NPC。

### FencedAreaOverlay

- 展示 FencedArea Place 范围、门、围栏边界和名称。
- 从 `WorldPlaceRegistry` 读取数据。
- 不作为 source of truth。

### WorldEntityRegistry

- 维护 NPC / item 的位置、持有关系和可查询 id。
- 提供 drop target resolve。
- 提供 `validate_forced_drop` 和 inventory transaction, 保证 grid occupancy 与 held state 同步。

### BuildingPlacementService

- 负责 Building/FencedArea footprint 的 occupancy 检查。
- 作为 `FencedAreaPlace` 创建和几何修改的唯一写入口。
- 禁止 footprint 覆盖 NPC 当前所在 cell。
- 校验每个 Building/FencedArea 都有合法 `door_cell`。
- 根据拖拽结束 cell 自动选择 `door_cell`。
- 禁止 Building/FencedArea footprint 互相交叉。
- 自动计算 `fence_cells` 和 `interior_cells`。
- 将 `fence_cells` 标记为 blocked, 保持 `door_cell` 和 `interior_cells` walkable。
- Building/FencedArea 影响 NPC 未来路径时, 通知 `NPCMover` / `TodoExecutor` 触发 replan。
- replan 失败时, 将当前 todo 标记为 `BLOCKED`。

### InteractionEventLog

- 记录玩家 drop、NPC encounter、Place 创建等事件。
- 给 feedback builder 和 todo planner 提供近期事件。

### NPCFeedbackBuilder

- 根据 InteractionEvent 和局部 world context 生成 NPC 反馈。
- 输出可以是 LLM 文本, 但必须绑定到一个已验证事件。
- 支持 streaming output, 并通过 `LLMClient` 接收 chunk。

### DailyTodoPlanner

- 每天早上调用 LLM 生成 todo list。
- 负责 schema validation 和 fallback。
- 不直接控制 UI。

### LLMClient

- 统一封装 LLM backend, 可以是 HTTP / WebSocket / local process。
- 支持 streaming chunk callback。
- 支持 request id、generation id、cancel token。
- late response 必须可丢弃。

### TodoExecutor

- 选择当前可执行 todo。
- 将 todo 编译成 action bundle。
- 响应 player interrupt、path blocked、replan failed。
- 当前 todo `BLOCKED` 后切换下一项。

### NPCActionScheduler

- 管理 `movement` / `speech` / `manipulation` / `cognition` lanes。
- 保证同一 lane 内互斥, 不同 lane 可并行。
- 允许 NPC 一边移动一边说话。

### NPCMover

- 负责 grid pathfinding 和 movement action。
- 维护当前 planned path。
- 目标在 Building/FencedArea 内部时, pathfinding 必须通过 `door_cell` 连通内外。
- 地图变化影响未来路径时触发 replan。

## 首版验收标准

首版验收分为 P0 / P1。P0 是必须先能演示的 playable loop; P1 是同一份设计里的 AI-native 深化, 可以在 P0 可玩后接入。

### P0 playable loop

1. 玩家可以用 `WASD` 或屏幕边缘移动摄像机。
2. 玩家可以左键选中 NPC / 物品并拖拽。
3. 拖拽过程中只显示 hover / preview, 不触发正式反馈。
4. 物品 drop 到 NPC 身上后, NPC 持有该物品并生成反馈。
5. 已持有物品的 NPC 拒绝第二个物品并生成反馈。
6. 右键点击携带物品的 NPC 后, 物品落到 NPC 附近 cell, NPC 清空持有物。
7. 玩家可以在游玩中拖拽网格矩形创建 FencedArea Place。
8. FencedArea Place 保存 `name + description + footprint + door_cell + fence_cells + interior_cells`。
9. NPC 当前所在 cell 命中 Place 时, context 能拿到地点名和描述。
10. 每天早上 NPC 能由 mock 或同步 LLM backend 生成结构化 todo list。
11. Runtime 能丢弃无效 todo item 并 fallback。
12. Save/load 后 `FencedAreaPlace`、NPC 持有物、物品位置不漂移。
13. 玩家不能放置 footprint 覆盖 NPC 当前所在 cell 的 Building/FencedArea。
14. 玩家在 NPC 未来路径上放置 Building/FencedArea 后, NPC 会 replan; replan 失败时当前 todo 变为 `BLOCKED` 并切换下一项。
15. MVP 阶段 NPC / 物品 / 建筑 / Place 都可以用 Godot 基础图形、emoji 和文字标签显示。
16. 每个 Building/FencedArea 都是矩形 grid 区域, 且必须有一个 non-corner 门 cell; fence 边界阻挡, 门和内部可走, NPC 自主移动只能通过门进出。
17. Building/FencedArea 创建时会原子注册为 `FencedAreaPlace`, NPC todo 可以直接引用同一个 `place_id`。
18. Building/FencedArea 的门默认自动选择为拖拽结束边缘最近的合法 boundary cell。
19. Building/FencedArea 不允许互相交叉或覆盖已有门。

### P1 AI-native async loop

1. NPC feedback / conversation 支持 streaming output。
2. 玩家干预可以打断当前 todo 和相关 LLM operation。
3. NPC 可以在移动时同时说话, 但同一 NPC 不能同时执行两个 movement action 或两个 speech stream。
4. `LLMOperation` late response 会被 operation id + generation check 丢弃。
5. daily todo streaming cancel 后不会 commit partial JSON。

## 首版不做

1. 不做自由多边形地图选区。
2. 不做复杂地点规则, 如营业时间、阵营权限、事件条件。
3. 不让 LLM 直接扫描全地图。
4. 不做完整剧情 trigger system。
5. 不做多人协作地图编辑。
6. 不做大型 UGC editor。
7. 不做多物品 inventory。
8. 不做拖拽 hover 即时反馈; 正式反馈只在 drop 后触发。
9. 不引入外部 sprite、tileset、动画、角色 rig 或正式美术资源 pipeline。
10. 不做建筑内部房间、室内导航或多门系统; 首版只支持单门矩形 Building/FencedArea。
11. 不允许 Building/FencedArea 重叠、嵌套或交叉。
12. MVP 不做普通 Place 创建工具; 玩家创建的地点都必须是 FencedArea Place。

## 设计结论

首版系统由三层组成:

1. **Player Interaction Layer**
   - 选择、拖拽、drop、右键丢弃。
2. **World Fact Layer**
   - Place、实体位置、持有关系、事件日志。
3. **AI NPC Layer**
   - drop feedback、daily todo list、基于 Place 的自主行为。

这样玩家可以用简单操作改变世界事实, NPC 可以用 LLM 理解并回应这些事实, 同时 Godot runtime 保持结构化、可验证、可存档。
