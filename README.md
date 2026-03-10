

# SS Lab Platform

Industrial lab data pipeline for rubber compound and tire bladder testing machines.

This project converts **lab machine test data** into a structured, reliable, and auditable data stream suitable for analytics and dashboards.

The system is designed for factory environments where:

* lab machines store data in **MDB databases**
* results are often **manually recorded or copied to Excel**
* historical data is difficult to query or analyze
* quality issues cannot be detected quickly

The SS Lab Platform solves this by building a **lightweight automated pipeline**:

```
Lab Machine MDB
      ↓
Extractor
      ↓
ALL_Values.csv
      ↓
Labtool (processing)
      ↓
snapshots + delta + state
```

Later phases will publish the results to **Feishu dashboards** and analytics systems.

---

# Project Philosophy

The system follows three principles:

### 1. Prove it works

First build a **reliable working pipeline**.

### 2. Make it reliable

Add logging, safe writes, scheduling, and safeguards.

### 3. Expand later

Publishing systems, monitoring, and alerts are added only after the pipeline is stable.

---

# System Architecture

The platform is divided into **three layers**.

## Layer 1 — Extraction

Reads machine database and converts it to CSV.

```
MDB database
     ↓
Extractor script
     ↓
ALL_Values.csv
```

Characteristics:

* MDB is **never modified**
* CSV is a **snapshot mirror**
* CSV is **overwritten every run**

History is **not managed at the extractor level**.

---

## Layer 2 — Processing (Labtool)

Detects data changes and generates structured updates.

```
ALL_Values.csv
      ↓
split_and_delta()
      ↓
snapshots/
delta/
state/
```

Outputs:

### Snapshot

Full current dataset for debugging.

```
snapshots/
    MDR-195-15__snapshot.csv
    MOONEY__snapshot.csv
    SCORCH__snapshot.csv
```

Snapshots represent the **latest known state of the stream**.

---

### Delta

Append-only update history.

```
delta/
   2026-03-10/
       MDR-195-15__delta.csv
       MOONEY__delta.csv
```

Each row is tagged:

```
NEW
CORRECTION
```

Delta files allow:

* audit trails
* historical replay
* reliable downstream publishing

---

### State Database

```
state/index.sqlite
```

Stores:

```
unique_key → last_hash
```

Used to detect:

```
NEW rows
CORRECTED rows
```

---

## Layer 3 — Publishing (future)

Not implemented yet.

Future pipeline:

```
delta
 ↓
Labgateway
 ↓
Feishu dashboards
```

Publishing will use **cursor-based ingestion** to prevent duplicates.

---

# Data Identity Model

Each record is uniquely identified using:

```
unique_key = source_id : method_code : ID
```

Example:

```
MDR_PC_01:MDR-195-15:7416
```

Why this is necessary:

| Field      | Problem                 |
| ---------- | ----------------------- |
| ID         | resets per method       |
| MethodName | Chinese text            |
| MDB        | rows may be overwritten |

The identity model guarantees **stable identification across runs**.

---

# Method Code Derivation

`method_code` is automatically derived from `MethodName`.

Examples:

| MethodName | method_code |
| ---------- | ----------- |
| 195℃测试15分钟 | MDR-195-15  |
| 焦烧         | SCORCH      |
| 门尼         | MOONEY      |

If parsing fails:

```
safe_slug + short_hash
```

is used as fallback.

This ensures the system is **zero-maintenance** even if lab software changes.

---

# Stream Model

Each machine/test combination becomes a **stream**.

```
stream_id = source_id__method_code
```

Examples:

```
MDR_PC_01__MDR-195-15
MDR_PC_01__MDR-195-30
MOONEY_PC_01__MOONEY
MOONEY_PC_01__SCORCH
```

Benefits:

* prevents mixing test types
* enables independent processing
* simplifies publishing later

---

# Delta File Rules

Delta files follow strict rules.

### One file per stream per day

Example:

```
delta/2026-03-10/MDR_PC_01__MDR-195-15__delta.csv
```

---

### Append-only

Delta files are **never rewritten**.

Benefits:

* auditability
* safe crash recovery
* deterministic downstream processing

---

# Crash Safety

State updates occur **only after delta write succeeds**.

Correct order:

```
write delta file
flush disk
commit state database
```

If a crash occurs:

```
delta written
state not updated
```

Worst case: duplicate row.

This is safe.

---

# Repository Structure

```
ss-lab-platform/

src/
    labcore/
        hashers.py
        keys.py
        methods.py

    labtool/
        split_and_delta.py
        extract_aggregate_mdb.py

scripts/
    windows/
        run_extract_aggregate.bat

tests/
    test_delta_logic.py
    test_keys_and_hash.py
```

---

# Output Structure

Example machine deployment:

```
C:\SSLab\MDR_PC_01\

    ALL_Values.csv
    source_id.txt

    out/

        snapshots/
            MDR-195-15__snapshot.csv

        delta/
            2026-03-10/
                MDR-195-15__delta.csv

        state/
            index.sqlite
```

---

# Deployment Model

Each machine runs the pipeline locally.

Example:

```
MDR_PC_01
MOONEY_PC_01
MDR_PC_02
```

Each machine has:

```
ALL_Values.csv
source_id.txt
out/
```

The filename `ALL_Values.csv` is the same across machines because the **folder path defines the machine context**.

---

# Windows Execution

Typical workflow:

### Extract data

```
run_extract_aggregate.bat
```

Produces:

```
ALL_Values.csv
```

---

### Run processing

```
python -m labtool.split_and_delta
```

Produces:

```
snapshots
delta
state
```

---

# Validation Checklist

Successful pipeline behavior:

### First run

```
NEW rows > 0
```

---

### Second run

```
NEW rows = 0
CORRECTIONS = 0
```

---

### After new lab test

```
NEW rows = 1
```

---

### After editing historical row

```
CORRECTION = 1
```

---

# Planned Improvements

Next improvements include:

* MDB copy-before-read (prevent database locks)
* pipeline logging
* atomic CSV writes
* Windows Task Scheduler automation
* schema drift detection

---

# Future Phases

Later development will include:

### Labgateway

Publishing layer.

```
delta
 ↓
Feishu API
 ↓
Dashboards
```

Features:

* cursor-based ingestion
* deduplication
* alert triggers
* monitoring

---

# Development Workflow

Always keep both machines synchronized.

### After modifying code

```
git status
git add .
git commit -m "message"
git push
```

### On another computer

```
git pull
```

---

# Learning Note

This project is intentionally designed so the developer can **learn while building**.

All guidance should explain:

* what each command does
* why the code change is necessary
* expected results
* failure scenarios

---

# License

Internal project for SS Machinery / SS Bladder digitalization initiative.

---

