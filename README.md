# proj-sync (`ax`) — an agentic harness for project delivery

A Claude Code plugin that runs the full lifecycle of a delivery project — proposal →
award → execution → audit → close — as agents over a deterministic filesystem, with
GitHub as the source of truth and Slack, Notion and Google Drive as connectors.

Built as a personal project to solve my own problem: running ~20 concurrent programs
where the real failure mode was never "we didn't know the rule", it was
*"we believed we had met it, and hadn't."*

**v1.21.0** · 3 agents · 21 commands · 25 skills · 11 test suites · MIT
· [Korean README](README.ko.md) · [Architecture](docs/ARCHITECTURE.md) · [Diagrams](docs/DIAGRAMS.md)

> This is a **sanitized public mirror** — see [SANITIZATION.md](SANITIZATION.md).

## The ideas worth stealing

**Side effects ⊥ cognition (`A3`).** Downloads, pushes, document builds and git are
*scripts*. Analysis, strategy, drafting and evaluation are *agents*. They hand off
through the filesystem and nothing else, so an agent never holds a token and a script
never makes a judgment call. `pm` and `pl` deliberately lack the `Task` tool; when the
proposal pipeline needed real fan-out, that became a separate agent (`pp`) rather than
a loosening of the boundary.

**Everything is a folder.** Project state and knowledge are materialized as *real
directories*, not abstract metadata. The agent explores with `ls`, `tree` and `cat`
instead of querying an index. Documents are shredded into a physical knowledge map
(`quark/_mirror/_axon`) that replaces retrieval for this workload — no embeddings, no
vector store, and no hallucinated citations, because a path either exists or it does not.

**Two orthogonal lifecycles.** A sales axis (proposal → awarded → running → closed) and
an SDLC axis (kickoff → analysis → design → build → close) that is only meaningful while
running. `lifecycle.phase` decides which pipeline is live and which agent owns it.
Collapsing the two axes is what makes status reporting lie.

**One project = one folder = one repo = one registry row.** No global database, no
cross-project memory. Switching projects is `cd`.

**Structured data is the SSOT; documents are derivations.** JSON/YAML is authored;
Markdown for review and xlsx/hwpx/pptx for delivery are built from it. Hand-editing a
derivation is a defect, not a shortcut.

**Deterministic ⊥ narrative ⊥ dispatch (`H2`).** Facts are computed by scripts, prose is
written by agents, sending is done by scripts. This is what makes a weekly report
reproducible rather than a fresh act of authorship each week.

**Verification as a first-class axis.** A separate set of nine quality principles —
consistency, integrity, structure, lineage, logic, maintainability, operability,
security, performance — each shipped with its *violation signal* and *how to check*,
because principles are not violated out of ignorance.

## Layout

| Path | What |
|---|---|
| `plugin/ax/agents/` | `pm` (management) · `pl` (drafting) · `pp` (proposal orchestrator) |
| `plugin/ax/commands/` | slash commands — `init`, `sync`, `report`, `inbox`, `phase`, `doctor`, … |
| `plugin/ax/skills/` | 25 skills; cognitive ones carry `prompt.md` + a JSON output `schema.json` |
| `plugin/ax/scripts/` | side-effect entry points — parsers, builders (xlsx/hwpx/pptx), connectors, gates |
| `plugin/ax/templates/` | deterministic folder spec, config template, nine principles |
| `docs/design/` | design records: principles, orchestration spec, pipeline design |
| `tests/` | shell test suites — commit lint, encoding, structure gate, publish planning |

## Running it

```bash
bash build.sh          # → proj-sync.zip (self-contained from plugin/)
bash tests/test_structure_gate.sh
```

Install and operation notes are in [GUIDE.md](GUIDE.md) and [MANUAL.md](MANUAL.md)
(Korean). Third-party derivations are credited in [NOTICE](NOTICE).
