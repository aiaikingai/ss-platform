ss-lab-platform — DECISIONS LOG

This file records architectural decisions that affect identity, hashing, state handling, or output structure.

Rules:

Append-only.

Never delete past decisions.

If a decision changes, add a new entry explaining why.

2026-03-04
Decision 001 — Unique Key Model
unique_key = source_id : method_code : ID

Reason:

IDs reset per method/mode.

MethodName may be Chinese and change over time.

method_code allows identity stability across MDR and Mooney.

Keeps key short and deterministic.

Decision 002 — Method Code Derivation

MethodCode must be auto-derived.

Rules:

焦烧 → SCORCH

门尼 → MOONEY

Parse temperature + minutes for MDR methods (e.g., 195℃测试15分钟 → MDR-195-15)

Fallback: safe_slug(MethodName) + short hash

Reason:

Zero manual maintenance.

Future modes must work automatically.

Decision 003 — Record Hash Rules
record_hash = sha256(canonical_json_of_meaningful_fields)

Constraints:

Exclude ingest_time.

Exclude volatile fields.

Use sorted JSON canonicalization.

Deterministic output required.

Reason:

Source DB overwrites rows.

Hash change indicates correction.

Decision 004 — SQLite State Safety

State must store: unique_key → last_hash.

State commit must occur AFTER delta file write.

Use bulk upsert.

Reruns must not create duplicate delta rows.

Reason:

Crash safety.

Idempotency.

Prevent silent data loss.

Decision 005 — Output Structure (Option A)

Each machine must have its own output root:

out_root/
    snapshots/
    delta/YYYY-MM-DD/
    state/index.sqlite

MDR and Mooney must not share state.

Reason:

Prevent cross-machine collisions.

Keep system modular and scalable.

END OF DECISIONS LOG

