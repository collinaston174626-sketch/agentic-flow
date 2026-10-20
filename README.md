# Agentic Flow

**A lightweight, model-agnostic framework that turns any LLM agent into a
disciplined delivery pipeline: plan → execute → adversarially verify → rework
until it converges.**

No runtime, no dependencies, no SDK. Agentic Flow is a protocol plus three
prompts. If your agent can spawn sub-agents (or you can run three separate chat
sessions), you can use it today.

```
        ┌──────────┐   PLAN.md    ┌──────────┐  SUMMARY_rN.md  ┌─────────────┐
 task ─▶ │ PLANNER  │ ───────────▶ │ EXECUTOR │ ──────────────▶ │ VERIFICATOR │
        └──────────┘              └──────────┘                 └──────┬──────┘
              ▲                        ▲   gaps (blocker/major)       │
              │ re-plan (once)         └────────────────────────────────┤
              └──────── escalation: no progress / stuck gap ───────────┤
                                                              ship ◀────┘
```

## Why

Single-agent runs fail in predictable ways: the agent forgets part of the task,
declares victory early, writes stubs, and marks its own homework. Agentic Flow
removes each failure mode structurally:

| Failure mode | Flow's countermeasure |
|---|---|
| Requirements silently dropped | Mandatory **coverage audit**: every sentence of the task becomes an `R-ID` mapped to tasks. Scope reduction is forbidden. |
| Agent grades its own work | A separate **adversarial verificator** reads real files and re-runs real commands; it never trusts the executor's report. |
| "Almost done" declared as done | Doubt counts as failure; partial = gap; `passed` is invalid with any open gap. |
| Endless rework / nitpicking | Gaps are **severity-classified** and must be **anchored** to a requirement or acceptance criterion. Only blocker/major gaps trigger rework; minors never do. |
| Loops that never end | Rework is **stopped by convergence** (no progress, stuck gap, regression pendulum, empty round), with a soft cap of 5 and a hard cap of 7 rounds. |
| Context window bloat | The orchestrator is thin; heavy work happens in sub-agents with fresh contexts, talking through small files on disk. |
| Work lost to a crash / limit | All state lives in `.flow/<date>_<slug>/` as plain files (PLAN, SUMMARY_rN, VERIFICATION_rN). Resume from the last file. |
| "Please check it yourself" | Acceptance is automated: real browser/CLI/API runs, screenshots inspected with vision, DOM/API assertions. The user gets **decisions to make, never work to do**. |
| Vague "done" | Plans carry goal-backward `must_haves` (truths, artifacts, key links) and measurable `<done>` criteria. |

### Compared to other agent frameworks

| | Agentic Flow | Typical multi-agent frameworks | Plain "plan then do" prompts |
|---|---|---|---|
| Setup | Copy markdown files | Install a framework, write code, run a server | None |
| Lock-in | None — any LLM, any agent harness | Specific SDK / language / vendor | None |
| Independent verification | Built in, adversarial | Usually optional or LLM-as-judge on the same context | None |
| Stop condition | Convergence-based with caps | Fixed iteration count or manual | None |
| Audit trail | Versioned files per round | Logs / traces | Chat history |
| Token cost | Low — thin orchestrator, fresh contexts | Often high — shared growing context | Low |
| Human role | Approves the plan, decides escalations | Varies | Does the QA |

## The three roles

1. **Planner** — explores the project, derives *observable truths*, *artifacts*
   and *key links* (goal-backward), builds the requirements table, and writes
   `PLAN.md` with XML tasks (`<action>`, `<verify>`, `<done>`) in dependency
   waves. The plan is the executor's prompt and the verificator's contract.
2. **Executor** — implements every task in wave order, runs each `<verify>` for
   real, documents deviations, writes `SUMMARY_rN.md`. On rework rounds it fixes
   *only* the listed gaps, runs a regression check, and reports each gap as
   `closed`, `not closed`, `disputed` (with evidence) or `needs human decision`.
3. **Verificator** — read-only auditor. Checks truths, artifacts on four levels
   (exists, substantive, wired, data flows), key links, re-runs every `<verify>`,
   scans for debt (TODO/stubs/hardcoded data), audits requirement coverage, and
   writes `VERIFICATION_rN.md` with severity-classified gaps and a
   `ship | rework | escalate` recommendation. It adjudicates executor disputes
   and, on re-verification, re-derives its findings *before* reading its own
   previous report (anti-anchoring).

The **orchestrator** (your main agent) only routes context, keeps a ledger of
gap counts per round, decides whether to ship, rework or escalate, and writes
the final honest report.

## How it works, step by step

0. **Setup** — create `.flow/<YYYY-MM-DD>_<slug>/` in the project.
1. **Plan** — planner returns a plan; the human approves or sends feedback (any
   number of revisions). The approved plan is saved as `PLAN.md`.
2. **Execute (round 0)** — executor builds everything and writes `SUMMARY_r0.md`.
3. **Verify (round 1)** — verificator audits round 0 and writes
   `VERIFICATION_r1.md`.
4. **Decide**
   - `blocking_count == 0` → **ship**. Minors become residual remarks; they never
     trigger another round.
   - Otherwise, check **escalation triggers**: no progress, a gap surviving two
     attempts, a regression with no net improvement, an empty round, the
     verificator's own `escalate`, or the round caps. On escalation the human
     chooses: continue (max 2 more rounds), re-plan (once, fresh budget of 3
     rounds), or ship as is with an honest list of what is missing.
   - Else **rework**: the executor receives the blocking gaps verbatim and
     nothing else; return to verification.
5. **Report** — the orchestrator mirrors the last verification exactly. A run
   that did not converge is reported as **NOT CONVERGED**, never as done.

### Severity model

| Severity | Meaning | Blocks? |
|---|---|---|
| blocker | A requirement is unmet, an artifact is missing/stub, a `<verify>` fails | yes |
| major | Requirement met with a substantive defect or broken edge case | yes |
| minor | Cosmetics / taste / polish | no |

Doubt escalates severity upward; an unanchored finding is only an *observation*.
Both rules protect you from missed defects and from endless nitpicking.

## Repository layout

Flow is a standard **Agent Skill** (a folder with a `SKILL.md`), the open format
supported by Claude Code, Codex, Gemini CLI, Cursor and other agents.

```
skills/flow/
  SKILL.md                Orchestrator protocol (the skill itself)
  roles/
    planner.md            Planner instructions
    executor.md           Executor instructions
    verificator.md        Verificator instructions
  examples/PLAN.example.md  A sample plan
install.sh                Installs the skill into every agent found on your machine
LICENSE                   MIT
```

Nothing in the skill is vendor-specific. The three role files are loaded by the
orchestrator and handed to sub-agents as their instructions.

## Model tiers

Flow is model-agnostic; what matters is the capability tier per role.

| Role | Tier | Reference model |
|---|---|---|
| Planner | strongest available | Fable |
| Executor | strong | Opus |
| Verificator | strong | Opus |
| Orchestrator | any (it only routes) | session model |

On Claude Code, `install.sh` also registers native sub-agents pinned to exactly
these models. On other agents pick the closest equivalents and keep the planner
on your strongest model.

## Installation

```bash
git clone https://github.com/<you>/agentic-flow.git
cd agentic-flow
./install.sh            # add --dry-run to preview
```

The script copies `skills/flow` into `~/.claude/skills`, `~/.codex/skills`,
`~/.agents/skills`, `~/.gemini/skills` and `~/.cursor/skills` — only for agents
whose config folder exists. For Claude Code it additionally writes
`~/.claude/agents/flow-{planner,executor,verificator}.md` (models pinned).
Any other agent: copy `skills/flow/` into its skills folder by hand.

Restart your agent afterwards.

## Usage

- Claude Code: `/flow add CSV export to the reports page, with tests`
- Other agents: *"Use flow: add CSV export to the reports page, with tests."*

You review the plan first (approve or send feedback); then the pipeline runs on
its own and ends with an honest report. Artifacts land in
`.flow/<date>_<slug>/` of your project (add `.flow/` to `.gitignore` if you do not
want to commit them).

**Agent without sub-agents?** Run the three roles as fresh chat sessions: paste
`roles/planner.md` plus your task, save the output as `PLAN.md`; then
`roles/executor.md` plus the plan; then `roles/verificator.md` plus plan and
summary. Feed the verificator's gap list to a fresh executor session and follow
the stop rules in `SKILL.md`.

### Tips

- Give the planner real constraints (stack, conventions, files not to touch).
  Sub-agents see *only* what the orchestrator passes them.
- Keep production deployment out of the loop. The protocol defers deploys until
  after a clean verdict and your explicit approval.
- Tasks should take minutes to hours of agent work; for larger efforts run Flow
  once per milestone.

## Artifacts reference

| File | Written by | Purpose |
|---|---|---|
| `PLAN.md` | planner (or orchestrator after approval) | Requirements, `must_haves`, XML tasks, acceptance |
| `SUMMARY_r<N>.md` | executor | What was done, verify output, per-gap outcomes |
| `VERIFICATION_r<N>.md` | verificator | Verdict, severity-classified gaps, recommendation |

## Limitations

- Flow improves reliability and cost-efficiency; it cannot make a weak model
  strong. Verification quality is bounded by the verificator model.
- The protocol assumes the agent can run commands and read files. Purely
  conversational tasks gain little.
- Automated acceptance needs tooling (browser automation, test runners) available
  to the executor and verificator.

## Contributing

Issues and pull requests are welcome — adapters for other agent harnesses,
better examples, and prompt improvements especially. Keep everything in English
and keep the framework dependency-free.

## License

[MIT](LICENSE) — free for any use, commercial or not.
