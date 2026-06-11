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

Deployment architecture: TBD (central gateway vs distributed publishers).

Labtool/Labgateway design must remain compatible with both.

2026-06-11
Decision 006 — Unique Key Extended to 4 Parts
unique_key = source_id : method_code : ID : normalized_test_datetime
Supersedes the 3-part form in Decision 001. Reason: IDs may be reused if
machine/archive behavior changes; normalized test datetime adds a stable
event-identity component. Already implemented in keys.py; this entry
retro-documents it. Lesson: locked designs must get a log entry BEFORE the
code changes, not after.

Decision 007 — Append-Only Daily Delta Files
(Recovered: code referenced Decision 007 but it was never logged.)
One delta file per stream per day. Append rows each run; header written
only when file is new. fsync before SQLite state commit.

Decision 008 — Record Hash v2: Denylist + Drop-Empty
Hash includes all input columns EXCEPT extractor metadata (columns starting
with "__") and pipeline META_FIELDS. Empty values are omitted from the hash
payload. Reasons: (1) fixes silently missed Mooney/Scorch corrections caused
by an MDR-only allowlist; (2) makes hashes stable when new machine types add
columns to the union CSV; (3) zero per-machine maintenance, consistent with
Decision 002. Accepted consequence: one-time CORRECTION wave on first run
after deployment (no downstream consumer exists yet, so no migration script).

Decision 009 — Delta Files Are At-Least-Once
A crash between delta write and state commit can duplicate rows in a daily
delta file. By design: duplicates beat data loss. Contract: any downstream
consumer (labgateway) MUST deduplicate by (unique_key, record_hash).
