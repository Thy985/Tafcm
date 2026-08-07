FormulaFix Debug Report
========================

This archive contains diagnostic data for debugging.

Files:
  metadata.json           - App version, device, OS, session info
  trace.json              - Interaction + Command + Transaction traces
  snapshot.json           - Error snapshot (if any)
  invariant_report.json   - Invariant checker results

For analysis:
  python tools/ffx-analyze/analyze.py this_file.zip
