# Agentic Flow

**A delivery pipeline for Claude Code: plan → execute → adversarially verify →
rework until it converges.**

Agentic Flow is one slash command (`/flow`) and three native Claude Code
sub-agents (`flow-planner`, `flow-executor`, `flow-verificator`). The command
turns your main session into a thin orchestrator that routes context between
the three agents, keeps a ledger of every round and stops by convergence — not
by a fixed counter. No runtime, no SDK, no dependencies beyond Claude Code
(plus `python3` for the optional context meter).

```
                 PLAN.md                 SUMMARY_rN.md                 VERIFICATION_rN.md
 task ─▶ PLANNER ───────▶ EXECUTOR (rN) ──────────────▶ VERIFICATOR (always new) ─┐
           ▲                  ▲                                                    │
           │                  └──── blocking gaps only (rework) ◀──────────────────┤
           ├── REPLAN-CLASS: the same class of gap came back ◀─────────────────────┤
           └── REPLAN: no progress / stuck gap / pendulum ◀─────────────────────────┤
                                                       ship (0 blocking gaps) ◀─────┘
```

> **v2 — breaking change.** Version 1 of this repository shipped Flow as an
> Agent Skill (`skills/flow/`). That approach was wrong for Claude Code: the
> roles were plain prompts, not real sub-agents with their own model, effort and
> tool set. Flow is now a **slash command + three sub-agents**. `install.sh`
> moves a v1 skill out of the way automatically (see
> [Upgrading from v1](#upgrading-from-v1)).

## Why

Single-agent runs fail in predictable ways: the agent forgets part of the task,
declares victory early, writes stubs, grades its own homework and burns tokens
re-reading an ever-growing context. Flow removes each failure mode
structurally:

| Failure mode | Countermeasure in Flow |
|---|---|
| Requirements silently dropped | The planner turns every sentence of the task into a requirement ID mapped to tasks; scope reduction is forbidden. |
| Agent grades its own work | A separate verificator re-reads real files and re-runs real commands. It is a **new agent in every round** — a verificator that remembers its earlier verdicts confirms itself. |
| "Almost done" reported as done | Doubt escalates severity; any open blocking gap makes the final report "НЕ СОШЛОСЬ" (not converged). |
| Endless nitpicking | Gaps are severity-classified (blocker / major / minor) and must be anchored to a requirement. Minors never trigger a round — they go to a minor register that the next `/flow` run closes. |
| The same bug keeps coming back in new shapes | Gaps carry a **class** (root mechanism). One repeat of a class triggers **REPLAN-CLASS**: the planner must prescribe a radically different approach before any more patching. |
| Loops that never end | Stop by convergence: no progress, stuck gap, regression pendulum, empty round. Soft cap 5 rework rounds, hard cap 7. |
| Context rot and token burn | Thin orchestrator; heavy work in fresh sub-agent contexts; measured context hand-off at 300k tokens; executor continued only while its context is ≤ 150k. |
| Work lost to a session limit or crash | All state is plain files in `.flow/<date>_<slug>/`; a cut-off agent is resumed with `SendMessage`; long runs live in background processes. |
| "Please check it yourself" | Acceptance is automatic (real browser, screenshots inspected with vision, DOM/API assertions). The user gets **decisions**, never manual QA work. |

## What is in the box

```
commands/
  flow.md                  /flow — the orchestrator protocol (slash command)
agents/
  flow-planner.md          Stage 1: PLAN.md with goal-backward criteria (also REPLAN / REPLAN-CLASS)
  flow-executor.md         Stage 2: implements the plan, writes SUMMARY_r<N>.md
  flow-verificator.md      Stage 3: adversarial audit, writes VERIFICATION_r<N>.md
scripts/
  flow_ctx.py              Measures a sub-agent's context fill from its transcript
install.sh                 Installer / updater / uninstaller
CHANGELOG.md
LICENSE                    MIT
```

The layout mirrors `~/.claude/`, so every file lands in the same relative path.

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code) with sub-agent
  frontmatter support for `model`, `effort` and `permissionMode`
  (tested on Claude Code 2.1.x).
- Access to the `opus` model alias; `fable` is used only on escalation rungs
  L≥2 of the class ladder and falls back to Opus `max` if unavailable.
- `python3` (optional) for `scripts/flow_ctx.py`; the protocol has an inline
  fallback.
- For automatic UI acceptance in web projects: Playwright (chromium) available
  to the executor and verificator.

## Installation

```bash
git clone https://github.com/<your-account>/agentic-flow.git
cd agentic-flow
./install.sh --dry-run   # preview
./install.sh             # install or update
```

The installer copies:

| From the repo | To |
|---|---|
| `commands/flow.md` | `~/.claude/commands/flow.md` |
| `agents/flow-planner.md`, `flow-executor.md`, `flow-verificator.md` | `~/.claude/agents/` |
| `scripts/flow_ctx.py` | `~/.claude/scripts/flow_ctx.py` (executable) |

It is idempotent: unchanged files are skipped, changed or foreign files are
backed up to `~/.claude/.flow-backup/<timestamp>/` before being overwritten,
and every installed file is compared byte-for-byte with the repo at the end.
Restart Claude Code afterwards.

| Option | Effect |
|---|---|
| `--dry-run` | Show what would happen, change nothing |
| `--uninstall` | Remove the five installed files (backups kept) |
| `--no-backup` | Overwrite without saving previous versions |
| `FLOW_HOME=/path` | Install into another home directory |

**Recommended session settings** (`~/.claude/settings.json`): `"model": "opus"`
and `"effortLevel": "high"` for the orchestrator session.

### Upgrading from v1

v1 installed `~/.claude/skills/flow/` (a skill) and generated agent files from
role prompts. `./install.sh` detects the v1 skill, moves it to the backup
directory (a skill and a command both named `flow` would collide) and replaces
the generated agents. v1 also copied the skill into `~/.codex`, `~/.agents`,
`~/.gemini` and `~/.cursor`; v2 is Claude Code-only and leaves those
directories untouched — delete `skills/flow` there by hand if you no longer
want it.

## Usage

```
/flow add CSV export to the reports page, with tests
```

1. **Plan.** The planner explores the project and returns a plan; Claude Code's
   native plan-approval window opens. Approve, or reject with feedback (any
   number of revisions).
2. **Execute → verify → rework** runs on its own until the verificator reports
   zero blocking gaps or the loop stops converging.
3. **Report.** An honest final report: status, round table (who executed,
   context size, REPLAN-CLASS runs, full test runs), class register, minor
   register, automatic-acceptance evidence, decisions only a human can make.

**Autonomous mode.** Put a phrase like «без вопросов», «полностью сам» or
«автономно» (or the English equivalent: *no questions, fully autonomous*) into
the task. Then there is no plan-mode window and no questions: the orchestrator
reviews the plan itself, every escalation becomes an automatic REPLAN, and only
irreversible actions or spending are left to you as decisions in the final
report.

**Headless** (`claude -p "/flow …"`): the planner writes `PLAN.md` directly, no
approval window.

Artifacts land in `<project>/.flow/<YYYY-MM-DD>_<slug>/`. Add `.flow/` to the
project's `.gitignore` if you do not want to commit them.

## How it works

### Roles

| Role | Model / effort | Job |
|---|---|---|
| Orchestrator (`/flow`) | your session (`opus`, `high`) | Routes context, keeps the ledger and `CLASS_REGISTER.md`, decides ship / rework / escalate, writes the final report. Never does the work itself. |
| `flow-planner` | `opus` · `xhigh` (REPLAN: `max`) | Requirements audit, observable truths, artifacts and key links (goal-backward), XML tasks with `<action>`, `<verify>`, `<done>` in dependency waves, an «Инварианты» section. Modes: APPROVAL, FILE, REPLAN, REPLAN-CLASS. |
| `flow-executor` | `opus` · `high` (`xhigh`/`max` only on class escalation) | Implements every task, runs every `<verify>` for real, freeze gate before the single final full test run, writes `SUMMARY_r<N>.md` with a «Передача преемнику» hand-off section. Runs with `permissionMode: bypassPermissions`. |
| `flow-verificator` | `opus` · `xhigh`; tools `Read, Glob, Grep, Bash, Write` (writes only its report / hand-off files) | Checks truths, artifacts on four levels (exists, substantive, wired, data flows), key links; re-runs every `<verify>`; mechanism check from round 1; probes repeating classes with fresh instances it invents; anti-anchoring on re-verification. |

The `opus` alias always resolves to the newest Opus — versions are never
pinned. Fable is an escalation rung, not a default.

### Escalation ladder for a repeating gap class

| Rung | Planner | Executor of the next round |
|---|---|---|
| default | `opus` · `xhigh` | `opus` · `high` |
| REPLAN-CLASS L=1 | `opus` · `max` | fresh, `xhigh` |
| REPLAN-CLASS L=2 | `fable` · `max` | fresh, `xhigh` |
| REPLAN-CLASS L≥3 | `fable` · `max` | fresh, `max` |

A rung is sticky until a verificator confirms the class closed on fresh
instances. Each new REPLAN-CLASS must reject the approach the previous one
prescribed.

### Stop rules

After every verification, in this order:

1. **Ship** — `blocking_count == 0`. Minors go to `.flow/MINOR_REGISTER.md`.
2. **Class repeat** → REPLAN-CLASS, then a fresh executor.
3. **Escalate** — no progress, stuck gap (survived two attempts), pendulum
   (regression without net improvement), empty round, verificator says
   `escalate`, soft limit 5 / hard limit 7. Interactive: you choose continue /
   replan / ship as is. Autonomous: automatic REPLAN.
4. **Rework** — only the blocking gaps, verbatim. The previous executor is
   continued (`SendMessage`) only if its measured context is ≤ 150k and no
   reuse prohibition holds (compaction, agent gone from `ListAgents`,
   REPLAN/REPLAN-CLASS before the round, stuck gap or regression, a blocking
   gap waiting for a human decision, unreadable transcript, higher effort
   needed); otherwise a fresh executor.

Production deploy is never part of the loop: it runs as a separate step only
after a clean verdict and your explicit go-ahead.

### Token economy and resilience

- Cost ≈ Σ(tool calls × context size), so Flow keeps contexts small: reading
  diet, batched tool calls, plans over 60 KB read as header + own tasks.
- Long runs (tests, benchmarks) go to background processes; agents wait by
  ending their turn, not by polling.
- **Freeze gate:** frames, log audit and text QA happen *before* the single
  final full test run of a round; a full run confirms, it does not search.
- **Context hand-off:** any sub-agent at 300k tokens hands its work to a fresh
  agent of the same role via `HANDOFF_r<N>_<k>.md`
  (measured by `flow_ctx.py --self <FLOW_MARK>`).
- **Session limits:** a cut-off agent is resumed with `SendMessage`, not
  restarted; one hourly safety wake-up for the orchestrator in autonomous
  runs; no cron alarms, no chat-flooding monitors.
- **Orchestrator freedom for economy:** a stage whose outcome is already known
  may be skipped, disjoint stages may run in parallel — without lowering
  quality (the verificator is still always new, the freeze gate and the single
  full run stay).

### Artifacts

| File | Written by | Purpose |
|---|---|---|
| `PLAN.md` | planner (or orchestrator after approval) | Requirements, invariants, must-haves, XML tasks, acceptance |
| `SUMMARY_r<N>.md` | executor | What was done, verify output, per-gap outcomes, hand-off notes |
| `VERIFICATION_r<N>.md` | verificator | Verdict, severity-classified gaps with classes, recommendation |
| `CLASS_REGISTER.md` | orchestrator | Gap classes by round, fixes, REPLAN-CLASS history, escalation level |
| `STATE.md`, `HANDOFF_r<N>_<k>.md` | executor / any role | Live progress and in-round context hand-off |
| `../MINOR_REGISTER.md` | orchestrator | Open minors across runs; the next `/flow` run closes them first |

Executor rounds start at 0 (`SUMMARY_r0.md`); verification round K audits
executor round K−1.

## Configuration

Tunable constants live in `commands/flow.md`, section «Agent reuse policy»:

| Constant | Default | Meaning |
|---|---|---|
| `REUSE_MAX_CTX` | 150000 | Max executor context to continue it into the next round |
| `CTX_HANDOFF` | 300000 | In-round hand-off threshold for every role (also env `FLOW_CTX_HANDOFF` for `flow_ctx.py`) |

`300k` is also written out in the «Context handoff at 300k» sections of the
three agent files — change it there too if you change `CTX_HANDOFF`.
Models and effort levels are in each agent's frontmatter and in «Model &
effort policy».

## Glossary

| Term | Meaning |
|---|---|
| round `rN` | One executor pass (`SUMMARY_rN`) or one verification (`VERIFICATION_rN`) |
| blocking gap | A `blocker` or `major` gap; only these trigger rework |
| class | The root mechanism behind a gap, independent of the concrete instance |
| REPLAN-CLASS | Planner run that replaces the failing approach for a repeating class |
| FREEZE | Point after which no code changes enter the round before its final full run |
| full run | The project's complete test suite; one per round, last, as confirmation |
| hand-off | Transfer of a role's work to a fresh agent at 300k context (`HANDOFF_r<N>_<k>.md`) |
| `FLOW_MARK` | Unique token in each sub-agent prompt so it can find and measure its own transcript |
| ledger | The orchestrator's per-round record that drives every ship/rework/escalate decision |

## Language

Protocol prose is mixed English/Russian; the reports and artifacts Flow writes
are in Russian, agent-internal keys stay English (hard rule 6 of the command).
Change that rule if you want artifacts in another language.

## Limitations

- Flow improves reliability; it cannot make a weak model strong. Verification
  quality is bounded by the verificator model.
- It assumes the agents can run commands and read files; purely conversational
  tasks gain little.
- Automatic acceptance needs real tooling (test runners, browser automation)
  available to the executor and verificator.
- `flow-executor` runs with `permissionMode: bypassPermissions`. Remove that
  line from `agents/flow-executor.md` if you want permission prompts.

## License

[MIT](LICENSE)
