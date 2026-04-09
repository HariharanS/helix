---
applyTo: '**/Infrastructure/**'
---

- Single-table design — PK and SK per entity type, no table-per-entity
- Query, never Scan — Scan is a code smell, always use a key condition
- Use `begins_with` for SK range queries
- Always project specific attributes — avoid fetching full items when only a subset is needed
- Pagination via exclusive start key (cursor-based), not offset
- Use `TransactWriteItems` for multi-item writes that must be atomic
- GSIs only when the primary key pattern doesn't support the access pattern
- Keep entity mappings close to the repository class — no separate ORM layer
