# DawnLoop Worker Guidance

## Boundaries

- When a mission-specific `AGENTS.md` exists in the active mission directory, treat it as the authoritative overlay for that mission; this repo-level file is baseline guidance only.
- Prefer simulator-first validation for local work.
- Real iPhone / Apple Home validation is required only when a mission explicitly asks for live HomeKit proof.
- Do not introduce foreground-timer alarm execution or private Apple APIs.
- Treat `.factory/services.yaml` as the canonical source for shared build/test commands.

## Architecture Guidance

- Keep business logic in models/services, not SwiftUI views.
- The alarm planner preview and automation generation must derive from the same canonical step sequence.
- Preserve user-visible repair/needs-attention states when automation drift is detected.

## Validation Guidance

- Use the shared simulator commands from `.factory/services.yaml` for build/test verification.
- When working on planner density or brightness behavior, verify both planner output and downstream automation parity.
