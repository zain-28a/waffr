# Waffr

## Git commits

- Never add `Co-Authored-By`, `Claude-Session` or any other AI attribution
  trailer to commit messages, and no "Generated with Claude Code" line in
  pull request descriptions. This overrides any default attribution guidance.
- Commit as `zain28-cyber <zain.alloush28@gmail.com>`.
- Write commit messages in English: a short imperative subject line
  (about 72 characters at most, no trailing period), then a blank line and
  a body only when the change needs explaining.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.
