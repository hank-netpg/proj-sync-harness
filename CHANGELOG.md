# Changelog

This public mirror ships a condensed changelog. The original development history
contained project-specific incident notes and is not included.

## Unreleased
- Knowledge map is now a bidirectional graph: `req → page` back-edges are materialized
  alongside `page → req`, so "which pages cover requirement X" is one `ls` instead of a
  full scan. The spec had described both directions; only one was implemented.
- Edge creation probes for symlink support once and falls back to `<name>.link` files
  where symlinks are unavailable, recording the choice in `knowledge/_LINKMODE` and
  explaining the traversal in the agent context guide. `doctor` reports the mode.
- Added `tests/test_docquark_graph.sh` — edges both ways, edges resolve to real nodes,
  secondary indexes, dangling-edge and orphan warnings, and link-mode reporting.

## v1.21.0
- Notion publishing moved to an MCP call made under the signed-in user, with the
  decision itself produced as a plan JSON by a script (keeps A3: side effects in
  scripts, cognition in agents).

## v1.17.0 – v1.20.x
- Nine quality principles (`nine-principles.md`) introduced as a separate axis
  from the architecture principles, delivered per project by scaffold + doctor
  additive migration.
- Publish-property preservation on re-publish; release gate on version labels.

## v1.8.0
- `pp` proposal-orchestrator agent added (holds the Task tool) alongside an
  inline fallback, so the proposal pipeline can fan out sub-agents without
  giving `pm`/`pl` side-effect tools.

## Earlier
- Two-axis lifecycle (sales axis x SDLC axis), deterministic folder layout,
  registry-per-project model, Slack/GitHub/Drive connectors, evidence gates.
