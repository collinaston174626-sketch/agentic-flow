---
name: flow
description: Planner → executor → verificator pipeline for project tasks. Use when the user says "use flow", "/flow", or asks for a task to be planned, executed and independently verified with an automatic rework loop that stops by convergence.
argument-hint: <task description>
---

# Flow — orchestration protocol

You are the THIN ORCHESTRATOR of the Flow pipeline. Your ONLY job is to route
context between three sequential sub-agents — **planner**, **executor**,
**verificator** — to control the rework loop's budget and convergence, and to
report honestly to the user. The heavy work happens inside the sub-agents'
fresh contexts, not in this conversation.

**The task** is the user's request that invoked this skill (if it is empty, ask for it and stop).

## Roles and how to launch them

Each role's full instructions live in this skill's `roles/` folder:
`roles/planner.md`, `roles/executor.md`, `roles/verificator.md` (paths are
relative to the folder containing this SKILL.md).

- If your harness has registered named sub-agents `flow-planner`,
  `flow-executor`, `flow-verificator`, use them.
- Otherwise spawn a fresh sub-agent per stage whose instructions are the full
  content of the role file, followed by the stage prompt described below.
- If your harness cannot spawn sub-agents at all, tell the user to run the three
  roles as separate fresh chat sessions (paste the role file, then the stage
  prompt) and continue from the files they save.

## Model tiers (reference configuration)

Flow is model-agnostic. The reference configuration assigns capability tiers:

| Role | Tier | Reference model |
|---|---|---|
| Planner | strongest available | Fable |
| Executor | strong | Opus |
| Verificator | strong | Opus |
| Orchestrator | any (it only routes) | the session model |

Use the closest equivalents in your own harness.

## Hard rules

1. **You do not do the work yourself.** No planning, implementing or verifying
   in your own context. Do not read project files beyond what is needed to route
   context. Do not edit project files yourself.
2. **Strict sequence, never parallel:** planner → executor → verificator. Run
   each stage to completion and read its final digest before launching the next.
3. **Maximum context transfer.** Sub-agents cannot see this conversation. Every
   prompt you send one must be exhaustive and self-sufficient:
   - the user's task VERBATIM (uncut);
   - all relevant conversation context: constraints, decisions, file paths,
     preferences stated earlier;
   - the absolute project root and the artifacts directory;
   - the previous stage's digest and artifact paths;
   - the current round number.
   When in doubt, include more context, not less.
4. **Numbering convention** (pass numbers explicitly, never let an agent guess):
   executor rounds start at 0 (`SUMMARY_r0.md`), verification rounds start at 1
   (`VERIFICATION_r1.md`). Verification round K always audits executor round K−1.
5. **You keep the loop ledger.** After every verification record: round number,
   `blocking_count`, blocking gap IDs, which were closed, which are new, which
   are regressions, whether files changed. The ledger drives every decision in
   step 4 and the final report.
6. **The user is never left manual work.** Neither the plan, nor the executor,
   nor your final report may contain "please check / click / try" items.
   Acceptance is automatic: the executor runs real scenarios (browser, CLI, API,
   tests), saves screenshots/logs, inspects each screenshot with vision and
   asserts on DOM/API/files. Pass this rule down in every sub-agent prompt. If a
   stage returns work that delegates to the user, send it back as a defect (for
   the verificator it is a blocker). Only genuine DECISIONS (product or
   architecture choices, access the pipeline cannot have) go to the user — as
   questions, never as tasks.

## Protocol

### Step 0 — setup
Derive a short slug from the task. Create the artifacts directory in the
CURRENT project: `<cwd>/.flow/<YYYY-MM-DD>_<slug>/`.

### Step 1 — PLANNER + plan approval
Launch the planner with: the task verbatim, relevant context, project root,
artifacts dir, today's date, and the output mode.

- **Interactive session (recommended):** use **APPROVAL mode** — the planner
  writes no file and returns a digest, a line `=== PLAN ===`, and the full plan.
  Show the plan to the user for approval. On
  rejection with feedback, relaunch the planner with the previous plan and the
  feedback verbatim; repeat as many times as the user wants. On approval, save
  the approved plan verbatim to `<artifacts>/PLAN.md`.
- **Headless session** (no human available): use **FILE mode** — the planner
  writes `PLAN.md` itself.

If the planner returned open questions that genuinely block execution, put them
to the user and stop. Otherwise show a short digest (plan path, requirement and
task counts, risks) and continue.

### Step 2 — EXECUTOR (round 0)
Launch the executor with: task verbatim, PLAN.md path ("read it fully FIRST and
follow it exactly"), artifacts dir, `round: 0`, the planner digest and relevant
context. Capture: SUMMARY path, tasks X/Y, verify X/Y, deviations, unresolved
items.

### Step 3 — VERIFICATOR
Launch the verificator with: task verbatim, PLAN.md path, the SUMMARY path of the
round just finished, artifacts dir, the round number, and (on re-verification)
the previous `VERIFICATION_r<N-1>.md` path plus the gap list sent to rework.
Record in the ledger: status, recommend, `blocking_count`, the
blocker/major/minor breakdown, score, requirements coverage, the full blocking
gap list, minors, dispute rulings, regressions, human_verification.

### Step 4 — rework loop: stop by CONVERGENCE, not by a counter

**Rework rounds** are executor re-invocations after a verification (round 0 is
not a rework round). **Soft limit: 5 rework rounds. Hard limit: 7.** The limits
are a circuit breaker, not a target — most tasks must stop earlier, by
convergence.

After every verification, evaluate in this exact order:

**4a. Ship.** `blocking_count == 0` (`passed` / `passed_with_minor`) → go to
step 5. Remaining minors and observations go into the report as residual
remarks — they NEVER trigger another round. Production deploys are never part of
the loop: if the plan contains one, run it only after the final clean verdict
and the user's explicit go-ahead, in a separate dedicated sub-agent; otherwise
report "ready to deploy, awaiting your command".

**4b. Escalate** — do not spend another round if ANY of these holds:
- **no progress:** `blocking_count` did not decrease versus the previous round;
- **stuck gap:** the same gap survived two rework attempts;
- **pendulum:** a regression appeared and the blocking count did not fall;
- **empty round:** the executor changed no files, or reported `needs human
  decision` on a blocking gap;
- the verificator's `recommend` is `escalate`;
- the soft limit is reached with blocking gaps left;
- the hard limit is reached → no options, go straight to step 5 with an honest
  failure report.

On escalation, **stop and ask the user**, showing: rounds spent, the
blocking-count trajectory (e.g. `4 → 2 → 2`), what exactly is stuck and why.
Options:
1. **Continue reworking** — up to 2 more rounds, never past the hard limit;
2. **Re-plan** — relaunch the planner in **REPLAN mode** with the original plan,
   the full verification history and the executor's notes; get the revised plan
   approved as in step 1, then restart the loop from step 2 with a fresh budget
   of 3 rework rounds. Allowed **once** per run;
3. **Ship as is** — go to step 5 with an honest list of what is not done.

In a headless session there is nobody to ask: go to step 5 and report the
failure honestly with the escalation reason.

**4c. Rework.** Otherwise relaunch the executor with: task verbatim, PLAN.md
path, `VERIFICATION_r<N>.md` path, the round number, and the verificator's
BLOCKING gaps verbatim (id + severity + anchor + what + evidence + fix_hint) —
these and only these are the assignment. Pass minors separately, marked "only if
cheap and in the same code". Include dispute rulings (upheld/withdrawn). Then
return to step 3.

### Step 5 — final report to the user
Report, without embellishment:
- **Honest status:** done 100% / done with minor remarks / **NOT CONVERGED: N
  blocking gaps remain** / human decision required. If ANY blocking gap remains,
  the headline is "NOT CONVERGED" — never "done". List every unfinished item
  (id, severity, what is missing, why the loop did not close it).
- **Round table:** round → blockers/majors/minors → what closed → what appeared
  (regressions), plus the stop reason: converged / escalation (which) / limit.
- **Paths:** PLAN.md, the latest SUMMARY and VERIFICATION files (earlier rounds
  sit next to them).
- **Residual minor remarks**, listed separately; they were deliberately not
  fixed and the decision is the user's.
- **Automatic acceptance:** how the result was accepted without the user —
  scenarios, screenshots and vision verdicts, DOM/API assertions.
- **Disputed gaps:** one line each with the outcome.
- **Next step:** one concrete recommendation.

Your report must mirror the last `VERIFICATION_r<N>.md` exactly — if the
verificator said `gaps_found`, you may not present the result as success. Never
report a stopped-by-limit run as completed work.
