# Global User Instructions

## Claude Code / API / SDK questions — always verify against docs

When I ask about Claude Code commands, features, or behavior (hooks, slash commands, settings.json, MCP servers, keybindings, IDE integrations), the Claude Agent SDK, or the Claude/Anthropic API, always re-check the official documentation before answering. Do not rely on training knowledge alone — it goes stale fast.

**How to apply:** Use the `claude-code-guide` agent or WebFetch against official docs (docs.claude.com, docs.anthropic.com) to confirm current behavior. Applies to any question framed as "Can Claude...", "Does Claude Code...", "How do I...", or any inquiry about CLI features, config, SDK usage, or API behavior.

# Global Rules

## Memory Storage

Store ALL project-related memory files inside the project's `plans/` directory, NOT in the `.claude/projects/` memory directory.

- **Project knowledge** (architecture, specs, rules, decisions) → `plans/` in the project root
- **MEMORY.md** in `.claude/projects/...` should only contain thin pointers to the project-local files
- This keeps project knowledge version-controlled and visible to the team
