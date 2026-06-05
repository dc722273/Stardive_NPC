# NPC OpenRouter LLM 接线设计

> Status: 设计稿，待 review
> Date: 2026-06-04
> 关联 spec: `docs/superpowers/specs/2026-06-04-ai-native-npc-sandbox-core-design.md`

## 目标

把 NPC 的 daily todo 生成和 feedback 从当前的 deterministic mock / placeholder，接通到真实的 **OpenRouter** LLM 调用，模型固定使用 **`google/gemini-3.5-flash`**。api key 放在项目根 `.env`。

## 背景与现状

当前代码库**没有任何真实 LLM 网络层**，也没有 api key 配置入口：

- `scripts/npc/LLMClient.gd` 只是 operation/generation **状态机**（管理 streaming buffer、generation 版本、取消），不发请求、不读 key。
- `scripts/npc/DailyTodoPlanner.gd` 是**同步纯函数校验器**：接收已是 JSON 的 `raw_items: Array`，过滤非法 intent/target，空结果 fallback 到 `wander`。没有 LLM 调用入口。
- `scripts/npc/NPCFeedbackBuilder.gd` 的 `begin_feedback_stream` 已会调 `llm_client.start_operation(...)` 拿 operation，但**没有任何东西填充 streaming chunk**。
- `scripts/MainGame.gd` 第 217 行 `generate_daily_todo_hotkey_placeholder()`（按 `T`）塞的是假 todo（`intent: "sandbox_daily_placeholder"`，甚至不是合法 intent）。
- 无 `.env`，`project.godot` 无相关 setting，无环境变量读取。
- Godot 4.6.3 二进制位于 `tools/godot/`，已加入 PATH，可跑 headless 验证。

## 设计原则（AI Town 边界）

对齐既有 spec 的 "NPC Plan/Execute 与 LLM 接线" 章节：

> LLM 和 agent logic 可以异步生成计划或文本，但 Godot runtime 是唯一 world state truth。LLM 不直接改位置、不直接写 inventory、不直接改地图，只能提交结构化结果或流式文本片段；runtime 校验后再转成 action。

因此本设计中：LLM 只产出文本/JSON → 经 `LLMClient` 的 generation 守卫 → 经 `DailyTodoPlanner` 校验 → runtime 才采纳。LLM 永不直接改 world state。

## 架构

```
[.env] OPENROUTER_API_KEY / OPENROUTER_MODEL / OPENROUTER_BASE_URL
   │ 启动时读取
   ▼
LLMConfig (RefCounted)  ──── 提供 api_key / model / base_url / headers / enabled
   │
   ▼
LLMTransport (Node, 挂在 MainGame 的 NPCSystem 下)  ←── 唯一发 HTTPRequest/HTTPClient 的地方
   │  request_chat(messages, opts, callbacks)
   │  ├─ 非流式: HTTPRequest 一次拿完整 JSON
   │  └─ 流式:  HTTPClient 手动读 SSE，逐块回调
   ▼
LLMClient (RefCounted, 现状不变)  ←── operation/generation 状态机
   │  start_operation → (transport 回调回填) append_stream_chunk → complete_operation
   ▼
DailyTodoPlanner / NPCFeedbackBuilder
   │  拿到 LLM 产出的结构化文本/流
   ▼
validate_todos(...) / build_feedback(...)  ←── runtime 校验，唯一 world truth
```

## 组件职责

| 组件 | 类型 | 职责 | 依赖 |
|---|---|---|---|
| `scripts/npc/LLMConfig.gd` | RefCounted（新增） | 启动时解析项目根 `.env`，暴露 `api_key` / `model` / `base_url` / `headers()` / `enabled`。无 key 时 `enabled=false` | 无 |
| `scripts/npc/LLMTransport.gd` | **Node**（新增） | 唯一持有 `HTTPRequest` / `HTTPClient`。`request_chat(messages, stream, callbacks)`。非流式走 `HTTPRequest`，流式走 `HTTPClient` 读 SSE | `LLMConfig` |
| `scripts/npc/LLMClient.gd` | RefCounted（**不改**） | operation/generation 状态机。transport 的回调驱动其 `append_stream_chunk` / `complete_operation` | 无 |
| `scripts/npc/DailyTodoPlanner.gd` | RefCounted（**增量加方法**） | 新增 `request_daily_todos(npc, world, transport, llm_client, on_done)`：组 prompt → 发起调用 → 拿 JSON → 走现有 `validate_todos` → 写入 todo_list。现有 `validate_todos` 等纯函数**不动** | transport, llm_client |
| `scripts/npc/NPCFeedbackBuilder.gd` | RefCounted（**增量加**） | `begin_feedback_stream` 已拿 operation；补：用 transport 流式回填 chunk，完成时 commit | transport, llm_client |
| `scripts/MainGame.gd` | Node2D（**改 wiring**） | `_ready` 中 new `LLMConfig` + `LLMTransport`（挂 NPCSystem）；`T` 键从 placeholder 换成真实 `request_daily_todos` | 全部 |

## 数据流：daily todo（非流式）

1. 按 `T` → `MainGame` 对每个 NPC 调 `DailyTodoPlanner.request_daily_todos(npc, world, transport, llm_client, on_done)`。
2. planner 组 prompt：NPC 人格 + 可见 places / npcs / items + **强制 JSON schema 说明**。调 `llm_client.start_operation(npc_id, &"daily_todo")` 拿 operation + generation。
3. `LLMTransport.request_chat(messages, stream=false, response_format=json)` 发请求到 `{base_url}/chat/completions`。
4. 回调拿到完整 assistant content（应为 JSON 数组文本）→ `llm_client.complete_operation(op_id, json_text)`。`_is_valid_final_payload` 会对 `[`/`{` 开头的 payload 做 `JSON.parse_string`，非法则拒绝 commit。
5. commit 成功 → `JSON.parse_string` → `validate_todos(parsed_array, npc, entity_registry, place_registry, max_count)` 过滤非法 intent/target → 写入 `npc.todo_list`。
6. 任一失败（无 key / 网络 / 超时 / 非 JSON / late generation）→ fallback 到现有 `wander` todo，UI 给出提示。

## 数据流：feedback（流式）

1. 事件触发（如 `player_forced_drop_item`）→ `NPCFeedbackBuilder.begin_feedback_stream(event, npc, world_context)`。
2. 现有逻辑已 `start_operation(npc_id, &"feedback")` 拿 operation。
3. 补：`LLMTransport.request_chat(messages, stream=true, callbacks)`，`on_chunk` 回调中解析 SSE `data:` 行的 delta content → `llm_client.append_stream_chunk(op_id, delta)`。
4. SSE 结束（`data: [DONE]`）→ `llm_client.complete_operation(op_id)`（用累积 buffer）。
5. 每个 chunk 更新 UI feedback label（`MainGame.update_feedback_reaction`）。
6. late generation（玩家在流途中触发新 feedback）→ 旧 operation 的 chunk 被 `_is_current_operation` 丢弃（现有机制）。

## OpenRouter 接口契约（已联网核实）

- **Endpoint**: `https://openrouter.ai/api/v1/chat/completions`（OpenAI 兼容）
- **Headers**: `Authorization: Bearer <key>`、`Content-Type: application/json`；可选 `HTTP-Referer`、`X-Title`
- **Body**（非流式）：`{"model": "google/gemini-3.5-flash", "messages": [...], "response_format": {"type": "json_object"}}`
- **Body**（流式）：同上加 `"stream": true`，响应为 SSE，每行 `data: {json}`，结束 `data: [DONE]`
- **响应**（非流式）：`choices[0].message.content` 为 assistant 文本
- **响应**（流式）：每个 `data:` 的 `choices[0].delta.content` 为增量文本

> 注：`response_format: json_object` 要求 prompt 中显式说明"输出 JSON"。daily todo 的 JSON 顶层是数组，可包成 `{"todos": [...]}` 对象以兼容 `json_object` 模式，planner 解析时取 `.todos`。

## `.env` 格式

项目根 `.env`（不入库）：
```
OPENROUTER_API_KEY=dummy_openrouter_key
OPENROUTER_MODEL=google/gemini-3.5-flash
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
```

配套：
- `.gitignore` 增加 `.env`
- 入库 `.env.example`（不含真 key，仅占位说明）

`LLMConfig` 的解析规则：逐行读，跳过空行和 `#` 注释，`KEY=VALUE` 按第一个 `=` 切分，去除两侧空白和成对引号。`api_key` 为空 → `enabled=false`。

## 错误处理

| 情况 | 行为 |
|---|---|
| 无 key（`enabled=false`） | `request_daily_todos` 不发请求，直接 fallback wander；UI 提示 "LLM 未配置 (.env 缺 OPENROUTER_API_KEY)" |
| HTTP 错误 / 超时 | transport 回调带 error；planner fallback wander；记录事件 |
| 非 JSON 输出 | `complete_operation` 拒绝（`_is_valid_final_payload`）→ fallback |
| JSON 合法但 todo 全非法 | `validate_todos` 已有逻辑：fallback wander |
| late generation | 旧 operation 回调被 `_is_current_operation` 丢弃（现有机制），记 `llm_request_cancelled` |

## 测试策略

- **保留（不联网，原样绿）**：`apr/npc-loop/oracle/npc_loop_oracle.gd`、`tests/test_core_behaviors.gd` 的纯函数校验测试。这些路径**不经过 transport**，不受真实调用影响。
- **新增 deterministic 单测**：`LLMConfig` 的 `.env` 解析（注释/引号/空行/缺 key），纯函数。
- **新增联网集成测试**：`apr/npc-loop/oracle/llm_live_oracle.gd`。仅当项目根 `.env` 存在且有 `OPENROUTER_API_KEY` 时，真实调 OpenRouter，验证"能拿到合法 JSON 并通过 `validate_todos` 产出合法 todo"。**无 key 时打印 SKIP 并 `quit(0)`，绝不 FAIL**（保 CI 绿）。
- transport 的 SSE 解析逻辑抽成可单测的纯函数 `parse_sse_line(line) -> {type, content}`，对录制的 SSE 样本做 deterministic 单测，避免必须联网才能测解析。

## 文件清单

- 新增 `scripts/npc/LLMConfig.gd`
- 新增 `scripts/npc/LLMTransport.gd`
- 改 `scripts/npc/DailyTodoPlanner.gd`（增量加 `request_daily_todos`，纯函数不动）
- 改 `scripts/npc/NPCFeedbackBuilder.gd`（增量接 transport 流式）
- 改 `scripts/MainGame.gd`（wiring + `T` 键真实调用）
- 改 `.gitignore`（加 `.env`）
- 新增 `.env.example`
- 新增 `tests/test_llm_config.gd`（或并入 `test_core_behaviors.gd`）
- 新增 `apr/npc-loop/oracle/llm_live_oracle.gd`
- `LLMClient.gd` **不改**

## 实现后修复记录（对抗式审查 findings）

实现完成后经对抗式审查找出 8 条 finding，全部核验为真实。已修 4 条（2 major + 2 minor），其余 4 条 minor 作为已知技术债记录。

**已修：**
- **#1 (major) 多 NPC 撞单 HTTPRequest**：`LLMTransport` 加 FIFO 队列。in-flight 时新请求入队，完成后依次 dispatch。`request_daily_todos` 注入 `should_dispatch` 谓词（检查 `llm_client.current_operation_ids[npc::daily_todo] == op_id`，public var，无需改 LLMClient）：队列 dispatch 前若该 op 已被同 NPC 的更新 generation 取代，跳过真实网络调用（省钱），回 `superseded`。该路径有 deterministic 单测覆盖（`tests/test_planner_queue_llm.gd`，fake transport/llm_client）。
- **#2 (major) 新测试未接回归门**：4 个新测试（test_llm_config/transport/daily_planner_llm/feedback_builder_llm）从 `SceneTree`+`_initialize`+`quit` 改成 `RefCounted`+`run()->Array`，由 `tests/run_tests.gd` 统一聚合，纳入 `GODOT_TESTS: PASS` 回归门。
- **#3 (minor) daily todo 无界累加**：`MainGame._on_daily_todos_ready` 在 append 新 todo 前调 `_clear_pending_todos`，清掉该 NPC 还没开始的 `status==pending` todo（上一轮残留），保留 active/in-progress/blocked/done，不打断执行中的动作。daily planning 语义改为「重排当天计划」而非累加。
- **#4 (minor) late generation 注入 wander**：`request_daily_todos` 区分 commit `status`——`late`/`cancelled`/transport `superseded` 返回 `{ok:false, status, todos:[]}` 不注入任何 todo；仅 `invalid_payload`（非 JSON）/网络失败才 fallback wander。`MainGame` 收到 late/cancelled 时跳过 append。

**已知技术债（未修，记录待后续）：**
- #5 `_extract_choice_content` 未守卫 content 必须为 String（OpenAI structured content array 会被 `str()` 误转）。daily-todo 路径下 `parse_todos_payload` 会安全 fallback，影响低。
- #6 `NPCFeedbackBuilder._can_stream` 用 `transport._is_enabled()`（私有方法 duck-typing），未来 transport 改名会静默禁用流式。建议改公共 capability 接口。
- #7 `LLMConfig.headers()` 硬编码 `HTTP-Referer: https://localhost` / `X-Title`，不可配置。建议从 .env 读 `OPENROUTER_REFERER`/`OPENROUTER_TITLE` 或移除（OpenRouter 上可选）。
- #8 `load_from_project_root` 读 `res://.env`，导出包（PCK 只读）里读不到。dev 模式无影响；导出场景需另探 `OS.get_executable_path()` 目录。

## 真实 API 端到端验证（已完成，2026-06-04）

用户在项目根 `.env` 填入真实 key 后，已对真实 OpenRouter `google/gemini-3.5-flash` 完成端到端联调：
- 直连 transport 诊断：`status_code=200`、`ok=true`、模型对 "ping" 真实回 "pong"，content 非 fallback。
- `llm_live_oracle.gd` → `LLM_LIVE_ORACLE: PASS`。整条链路（`.env` 读 key → headers → POST chat/completions → 解析 choices[0].message.content → complete_operation JSON 守卫 → validate_todos）全通。

**首次联调发现并修复的真实 bug（"测试 PASS 但行为不对" 案例）：**
1. **HTTPRequest 未进树**：SceneTree 脚本 `_initialize()` 里 `add_child(transport)` 是 deferred 的，紧接着 `configure`/`request()` 时子 HTTPRequest `is_inside_tree()==false`，`request()` 返回 `ERR_UNCONFIGURED`。修复：`add_child` 后 `await process_frame` 再 configure/发请求。（MainGame 不受影响——它在 `_ready()` 里 add_child，节点已在树中。）
2. **fallback 掩盖失败 / oracle 假绿**：上述失败被 planner 的 fallback wander 吞掉，oracle 因 "wander 是合法 intent" 误判 PASS。修复：planner 结果加 `source` 字段（`&"llm"` 真实路径 / `&"fallback"` 兜底）；`llm_live_oracle.gd` 断言 `source==&"llm"`，拒绝 fallback 假绿。

## 追加：NPC 执行循环接线（2026-06-04，超出原 LLM 范围）

调试"为什么 NPC 不活动"时发现：原 P0 的 `MainGame._process` 只做 tick++/相机/重绘，**从未驱动 NPC 执行层**（`TodoExecutor`/`NPCMover`/`NPCActionScheduler` 有实现和 oracle 测试，但没接进主循环）。即生成了 todo 也无人执行。这是原始实现的缺口，非 LLM 接线引入。

**已接线（agentic-game-development 纪律，oracle 驱动）：**
- `MainGame` new + configure `TodoExecutor` / `NPCActionScheduler`，每个 NPC 懒创建 `NPCMover`（`_mover_for` 缓存）。
- 新增 `tick_npc_execution()`：遍历 NPC，取第一个 pending todo，经 movement lane 锁后 `execute_todo` 消费（瞬移式），完成释放 lane。
- `_process` 按 `npc_execution_interval`(0.8s) 节流调 `tick_npc_execution()`，NPC 自动活动。
- `_seed_sample_npc_item_data` seed 一个 `place_home`(door_cell 8,5) + 一个 visit_place 初始 todo，让启动后 NPC 立刻从 (4,4) 移动到 (8,5)（否则 todo_list 空、看起来静止）。

**Oracle：** `apr/npc-loop/oracle/npc_execution_loop_oracle.gd` —— pre-state（无 `tick_npc_execution`）FAIL_EXPECTED → post-state（NPC 移动 + todo done）PASS。

**调试中发现的执行层既有 bug（已规避，未修，记为后续）：**
- `TodoExecutor._target_cell` 对 `inspect_item`/`talk_to_npc` 返回 item/npc **本身所在格**，但 `entity_registry.move_entity_to_cell` 不允许 NPC 与 item/npc 重叠 → move 失败 → todo BLOCKED。正确行为应走到**相邻可达格**。seed 因此改用 visit_place（door_cell 可站）规避。

**已知行为限制（MVP，记为后续）：**
- 移动是**瞬移式**（一拍跳到目标，非平滑寻路动画）。
- todo done 后**不自动生成新 todo**，NPC 会静止，需按 `T` 触发 LLM/fallback 重排。持续自主活动（idle 时自动 wander/replan，避免全停在地图角落或每周期烧 key）是真功能，留待后续。

## 非目标（YAGNI）

- 不做多模型路由 / fallback 链。
- 不做 token 计费统计。
- 不做对话历史持久化（feedback 是一次性反应）。
- 不做 reflection / memory（spec 标为后续）。
- 不改现有 deterministic oracle 的断言。
