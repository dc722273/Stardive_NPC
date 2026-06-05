# APR workspace: playable-ui

两个目录,一条纪律。完整方法见 `agentic-apr` skill 的 SKILL.md。

## `oracle/` — frozen evidence(evaluator owns)
复现脚本、assertions、provenance 都放这里,并且必须在任何 fix 之前写好。
冻结之后,这个目录就是 fixer/generator 的 **read-only input**。如果你作为
fixer 认为 oracle 有问题:STOP,把理由交回给人或 evaluator,不要自己改。
(RAIL: evaluator-first + oracle read-only.)

这里每条 assertion 都要带 provenance:为什么这个 expected value 是对的,
来源是什么(design doc / ticket / user said so / engine invariant)?
(RAIL: provenance-on-write.)

## `scratch/` — throwaway scaffolding(fixer owns)
localize probes、one-at-a-time hypothesis scripts、extra dumps 放这里。可以自由写,
用完就丢。这里的东西没有 judgement power,最终 verdict 永远来自重跑 frozen oracle。

## F->P, the whole point
oracle script 必须在 fix 前 FAIL(证明你真的 reproduced the bug),fix 后 PASS
(证明 fix 真的被 frozen oracle 验过),并且用的是 SAME assertions。
从未红过的绿灯什么也证明不了。
