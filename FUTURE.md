# Future Plans — HomeStack

## Backend Migration: Bash → Python

The current backend is written entirely in Bash. While it works for the current scope, the codebase is hitting limitations in YAML parsing, error handling, SQL safety, and testability. The plan is to incrementally migrate core logic to Python (or another proper language), keeping Bash only where it makes sense.

### What Stays in Bash

- **setup.sh** — system-level bootstrapping, dependency installation, user/group creation. Bash is the right tool for this.
- **bin/homestack** — may remain as a thin entrypoint that dispatches to Python.

### What Moves to Python

| Component | Why |
|-----------|-----|
| `lib/yaml.sh` | Current parser is fragile regex — can't handle nested objects, quoting, or multi-line values. Python's `pyyaml` handles all YAML correctly. |
| `lib/db.sh` | No parameterized queries in Bash — `db_escape()` is a manual SQL injection band-aid. Python's `sqlite3` stdlib has proper parameterized queries. |
| `lib/secrets.sh` | String processing and file operations are error-prone in Bash. |
| `lib/registry.sh` | Git operations and path handling are cleaner in Python. |
| `lib/core.sh` | Locking, validation, and helper logic. |
| `lib/commands/*.sh` | All command logic (install, update, remove, backup, restore, etc.). The 140-line install.sh with manual rollback traps would be a simple try/finally in Python. |

### Migration Phases

1. **Phase 1:** Replace `yaml.sh` with a Python helper — `lib/yaml_helper.py` — that Bash calls via subprocess. Immediately fixes the fragile parser.
2. **Phase 2:** Move `db.sh` to Python — parameterized queries, proper error handling.
3. **Phase 3:** Move command logic to Python. `bin/homestack` becomes a thin Bash wrapper calling `python3 lib/main.py "$@"`.
4. **Phase 4:** Full Python CLI with `click` or `argparse`. Bash only remains in `setup.sh`.

### Why Python Over Other Options

- Debian/Ubuntu ship with Python 3 preinstalled — no new dependency
- Existing code is procedural, so translation is straightforward
- `pyyaml`, `sqlite3` stdlib, `subprocess` for Docker — all mature and well-documented
- `pytest` for testing — mocking, fixtures, coverage built in
- Contributors still only write YAML + Compose for apps — backend language doesn't affect them

### Alternatives Considered

- **Go** — single static binary (no runtime dependency), but higher learning curve and slower iteration for a project of this size
- **Rust** — same benefits as Go but even steeper curve, overkill for a CLI wrapper
- **Node.js** — not preinstalled on most servers, adds a heavy runtime dependency
