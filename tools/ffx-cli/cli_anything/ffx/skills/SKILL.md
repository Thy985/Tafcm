---
name: >-
  cli-anything-ffx
description: >-
  Command-line interface for Ffx - A Python CLI for the Tafcm Flutter project — diagnostic, ADI wrapper, and markdown analysis.
---

# cli-anything-ffx

A Python CLI for the Tafcm Flutter project — diagnostic, ADI wrapper, and markdown analysis.

## Installation

This CLI is installed as part of the cli-anything-ffx package:

```bash
pip install cli-anything-ffx
```

**Prerequisites:**
- Python 3.10+
- ffx must be installed on your system


## Usage

### Basic Commands

```bash
# Show help
cli-anything-ffx --help

# Start interactive REPL mode
cli-anything-ffx

# Create a new project
cli-anything-ffx project new -o project.json

# Run with JSON output (for agent consumption)
cli-anything-ffx --json project info -p project.json
```

### REPL Mode

When invoked without a subcommand, the CLI enters an interactive REPL session:

```bash
cli-anything-ffx
# Enter commands interactively with tab-completion and history
```


## Command Groups


### Cli Project

Project management: create, open, info, inject content.

| Command | Description |
|---------|-------------|

| `info` | Show project metadata and content analysis. |

| `set-field` | Set a project field (mutates the JSON file). |



### Cli Analyze

Analyze markdown content, ADRs, and project structure.

| Command | Description |
|---------|-------------|

| `adr` | List and analyze all ADRs in docs/ADR/. |

| `structure` | Show project directory structure summary. |



### Cli Adi

ADI (Agent Diagnostic Interface) commands — delegates to adi.dart.

| Command | Description |
|---------|-------------|

| `doctor` | ADI self-check. |

| `latest-error` | Get the latest error observation. |

| `trace-show` | Show a trace chain by ID. |

| `replay` | Replay a session. |

| `agent-context` | Generate Agent context Markdown. |

| `failures` | List recent failures. |

| `failure-show` | Show failure details. |

| `validate` | Validate after fix (replay + invariant). |

| `aggregate` | Aggregate observations into failures. |



### Cli Diag

Project diagnostics: health, version, environment.

| Command | Description |
|---------|-------------|

| `health` | Overall project health summary. |

| `version` | Show ffx-cli and project versions. |




## Examples


### Create a New Project

Create a new ffx project file.

```bash
cli-anything-ffx project new -o myproject.json
# Or with JSON output for programmatic use
cli-anything-ffx --json project new -o myproject.json
```


### Interactive REPL Session

Start an interactive session with undo/redo support.

```bash
cli-anything-ffx
# Enter commands interactively
# Use 'help' to see available commands
# Use 'undo' and 'redo' for history navigation
```


## State Management

The CLI maintains session state with:

- **Undo/Redo**: Up to 50 levels of history
- **Project persistence**: Save/load project state as JSON
- **Session tracking**: Track modifications and changes

## Output Formats

All commands support dual output modes:

- **Human-readable** (default): Tables, colors, formatted text
- **Machine-readable** (`--json` flag): Structured JSON for agent consumption

```bash
# Human output
cli-anything-ffx project info -p project.json

# JSON output for agents
cli-anything-ffx --json project info -p project.json
```

## For AI Agents

When using this CLI programmatically:

1. **Always use `--json` flag** for parseable output
2. **Check return codes** - 0 for success, non-zero for errors
3. **Parse stderr** for error messages on failure
4. **Use absolute paths** for all file operations
5. **Verify outputs exist** after export operations

## More Information

- Full documentation: See README.md in the package
- Test coverage: See TEST.md in the package
- Methodology: See HARNESS.md in the cli-anything-plugin

## Version

0.1.0