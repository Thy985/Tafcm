# Software-Specific SOP — Tafcm CLI

## Analysis

**Software**: Tafcm (Flutter + Dart)
**Type**: Mobile WYSIWYG Markdown editor with LaTeX/Mermaid support
**Backend**: Self-contained Dart library (no external binary)
**Data model**: `.md` files (single source of truth, ADR-0003)

## Existing Tooling

| Tool | Path | Language | Purpose |
|------|------|----------|---------|
| `adi` | `tools/adi/adi.dart` | Dart | ADI diagnostics (doctor, trace, replay, agent-context) |
| `ffx-analyze` | `tools/ffx-analyze/analyze.py` | Python | Parse ExportPipeline zip files |

## CLI Design Decisions

1. **Python over Dart**: CLI is Python so it can be used independently of Flutter/Dart SDK
2. **ADI delegation**: `ffx adi *` wraps `dart run tools/adi/adi.dart` — no reimplementation
3. **Project JSON**: `ffx project` operates on lightweight JSON files (not `.md` directly), since the Flutter app manages `.md` files internally
4. **Static analysis**: `ffx analyze` does regex-based counting — no Flutter runtime needed

## Command Groups

- `project`: CRUD on project JSON files
- `analyze`: Markdown/static analysis of project files
- `adi`: ADI diagnostic delegation
- `diag`: Health/version/environment inspection

## ADR References

- [ADR-0003](../../docs/ADR/0003-storage-single-source-md-files.md) — .md as single source of truth
- [ADR-0023](../../docs/ADR/0023-editor-observability-system.md) — Observability system
- [ADR-0024](../../docs/ADR/0024-agent-diagnostic-interface.md) — ADI design
