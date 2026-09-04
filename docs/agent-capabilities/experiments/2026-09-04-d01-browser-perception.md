# Experiment D-01 — Doubao 浏览器感知能力

- **id**: D-01
- **date**: 2026-09-04
- **agent**: doubao
- **environment**: cloud_computer (GUI browser tools: open_url_in_browser / take_screenshot)
- **capability**: browser navigation + page rendering + DOM/visual reading
- **task**: 打开真实 GitHub PR 页面并读取其状态
- **setup**: `open_url_in_browser https://github.com/Thy985/Tafcm/pull/251` → wait 4s → `take_screenshot`
- **steps**: 1) 导航 PR #251；2) 首次截图（加载中，OCR 将 Thy985 误读为 Tiny985）；3) 等待渲染；4) 二次截图（完整读取）
- **expected**: 能渲染并读取 PR 详情
- **actual**: 二次截图正确读取：Merged 状态、4 个 tab、merge 信息（"Thy985 merged 1 commit into main from docs/fix-guard-frontier-2026-09-04"）、关联 #241、失败 run #33799416096、Sign in 按钮（未登录）
- **status**: proven (navigation + rendering + reading)
- **boundary**: type: auth — GitHub 浏览器会话未登录，匿名公开读 OK，登录态操作不可用
- **boundary2**: type: perception — 首次加载空白需等待；OCR 对未完成渲染页面有误读风险
- **failure_mode**: 无（成功）；感知误差（Tiny985 vs Thy985）为一次性，渲染完成后消除
- **evidence**: screenshots (aka.doubaocdn.com/s/Iv255SV9ix → eSMILhISKh), DOM element extraction
- **evidence_strength**: visual
- **reproducibility**: high (deterministic public page)
- **notes**: 此实验同时确认 PR #251 已被 Human 合并（Guard 修复生效）；Doubao 浏览器能力可作为 Cline 无法做的真实世界验证的候选路径
