---
objective: You can trust it — dependency installation is correct, deduplicated, and ordered
status: complete
---

Production tier for dependency graph resolution. Replaces the recursive subprocess install pattern with up-front graph resolution, topological sorting, and deduplication.

## Completion Criteria

- `ppm install` resolves the full dependency tree before installing anything
- Shared dependencies (e.g., `mise` required by both `claude` and `ruby`) are installed exactly once
- Install order respects dependency ordering (leaves first)
- Cycle detection prevents infinite loops
- Error messages clearly identify missing or circular dependencies
