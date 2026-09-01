# Tafcm Agent Audit Index

> **定位**：Tafcm Maintainer Agent 每日 Audit 的历史索引（去重记忆的持久层）。
> **更新**：每次运行后由 `.github/scripts/tafcm-maintainer/update_index.py` 追加一行（CI 自动），不手工维护。
> **读取**：Agent 每次执行必须先读本表 + 近期 Audit，识别重复 Finding / 未解决 Finding / 长期技术债 / 趋势性问题——**避免每天重复报告同一问题**。
> **格式**：见 `.agent/tafcm-maintainer/SCHEMA.md` §5。

| Date | Findings | Issues | Ecosystem | Open Actions |
|------|----------|--------|-----------|--------------|
<!-- INDEX_ROWS: 由 update_index.py 在此行上方追加 -->
