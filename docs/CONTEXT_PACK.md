ss-lab-platform — CONTEXT PACK
1️⃣ Project Scope

Repo: ss-lab-platform
Purpose: Local lab data change-detection engine (Labtool) + Feishu publisher (Labgateway)

This repo handles:

MDR lab machines

Mooney lab machines (门尼 + 焦烧)

Future lab machines

It does NOT handle:

Feishu UI design

Business dashboards

Shipping systems

ERP

Those belong to SS Digitalization ARCH threads.

2️⃣ Core Reality Constraints

Source DB overwrites records (no history table).

IDs reset per method/mode.

Different machines are on different PCs.

System must require minimal maintenance for new modes.

System must be idempotent and crash-safe.

3️⃣ Locked Core Identity Model
unique_key
unique_key = source_id : method_code : ID

Where:

source_id = identifies the machine/PC (config file)

method_code = auto-derived from MethodName

ID = record ID within that method/mode

Reason:

IDs reset per method

MethodName may be Chinese

Identity must survive new modes

4️⃣ Method Code Derivation Rules

Must require zero manual maintenance.

Logic:

If MethodName contains:

焦烧 → SCORCH

门尼 → MOONEY

If MDR temperature/time detected:

Extract temperature + minutes

Example:

195℃测试15分钟 → MDR-195-15

180℃测试40分钟 → MDR-180-40

If parsing fails:

Fallback to safe_slug(MethodName) + short hash

No manual mapping required.

5️⃣ Record Hash Model
record_hash = sha256(canonical_json_of_meaningful_fields)

Rules:

Include meaningful technical fields only.

Exclude ingest_time.

Exclude volatile metadata.

Use sorted JSON for canonicalization.

Hash must be deterministic.

Purpose:

Detect corrections when DB overwrites rows.

6️⃣ SQLite State Model

State DB stores:

unique_key → last_hash

Requirements:

Crash-safe

Commit state only AFTER delta file write

Use bulk upsert

Reruns must not create duplicate deltas

7️⃣ Output Structure (Per PC — Option A)

Each machine has its own output root.

out_root/
    snapshots/
    delta/YYYY-MM-DD/
    state/index.sqlite

MDR and Mooney must not share state or output root.

8️⃣ Non-Negotiables

No manual mapping required for new modes.

Filenames sanitized (never raw MethodName).

Delta must only contain NEW and CORRECTION.

System must survive method renaming.

Idempotent reruns required.

Architecture changes must be recorded in DECISIONS.md.

9️⃣ Separation of Concerns

Labtool:

Extract

Normalize

Detect delta

Maintain state

Labgateway:

Publish delta to Feishu

Retry logic

Alert logic

Feishu UI:

Ledger tab

View tab

Alert display

Threshold tables

Feishu UI belongs to SS-ARCH threads, not this repo.

END OF CONTEXT PACK
