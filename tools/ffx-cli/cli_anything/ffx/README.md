# FormulaFix CLI (`ffx`)

A Python CLI for the FormulaFix Flutter project — diagnostic, ADI wrapper, and markdown analysis.

## Installation

```bash
cd tools/ffx-cli
pip install -e .
```

After installation, `ffx` is available in PATH.

## Prerequisites

- **Python 3.10+**
- **Dart/Flutter SDK** — required for ADI commands (`dart run tools/adi/adi.dart`)
- Run from the project root (`D:\Projects\Active\math2`) for ADI commands to work

## Usage

```bash
# Show help
ffx --help

# Project diagnostics
ffx diag health
ffx diag version

# Project management
ffx project create -o myproject.json -n "My Doc"
ffx project info -p myproject.json
ffx project inject formula -p myproject.json --latex 'E=mc^2'
ffx project inject heading -p myproject.json --text "Introduction" --level 1

# Markdown analysis
ffx analyze file README.md
ffx analyze adr
ffx analyze structure

# ADI commands (requires dart + running from project root)
ffx adi doctor
ffx adi latest-error
ffx adi trace show <trace-id>
ffx adi replay <session-id>
ffx adi failures
ffx adi validate <session-id>

# JSON output for agents
# Note: --json MUST come before the subcommand name
ffx --json diag health
ffx --json project info -p myproject.json
ffx --json analyze adr
```

## Command Groups

| Group | Description |
|-------|-------------|
| `project` | Create, inspect, and mutate project JSON files |
| `analyze` | Static analysis of markdown, ADRs, project structure |
| `adi` | Delegate to the native `tools/adi/adi.dart` CLI |
| `diag` | Health checks, version info, environment inspection |

## For AI Agents

Always use `--json` for parseable output:

```bash
ffx --json diag health
ffx --json analyze file README.md
```

Check `exit_code` and `status` fields in JSON output to detect errors.

**Important**: `--json` must appear **before** the subcommand (e.g., `ffx --json diag health`, not `ffx diag health --json`).
