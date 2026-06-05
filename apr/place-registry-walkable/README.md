# Agentic game development workspace: place-registry-walkable

两个目录,一条纪律。完整方法见 `agentic-game-development` skill 的 SKILL.md。

## `oracle/` — executable evidence
acceptance、reproduction、characterization、structural checks 都放这里。
实现阶段不要顺手改 oracle 来迁就补丁。如果 oracle 错了,停下,说明原因,
回到 evaluator phase 重新定义 pre-state。

这里每条 assertion 都要带 provenance:为什么这个 expected value 是对的,
来源是什么(design doc / ticket / user said so / engine invariant)?

## `scratch/` — throwaway scaffolding
localize probes、one-at-a-time hypothesis scripts、extra dumps 放这里。可以自由写,
用完就丢。这里的东西没有 judgement power,最终 verdict 永远来自重跑 frozen oracle。

## Pre/post contract
feature、bugfix、behavior change 通常是 FAIL_EXPECTED -> PASS。
纯 refactor 可以是 PASS_BASELINE -> PASS;若有结构目标,再加 structural oracle。
同一组 assertions 判 pre/post,不要在实现阶段改松它。
