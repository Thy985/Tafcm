# ADR-0021：仓库完整性策略（Repository Integrity Strategy）

> **状态**：Proposed
> **版本**：v1.4
> **生效日期**：2026-08-01
> **起草人**：AI Agent 起草（项目审计报告触发）
> **修订说明**：v1.4 微调 3 项 + 新增 1 项——① D6.3 升级条件"三全满足"过严导致 Agent 过度保守，改为 **R0-R3 风险分级**（R0 可逆 / R1 低风险 / R2 高风险 / R3 不可逆——仅 R3 需三全满足）；② `git-failure-log.md` 泛化为 **`agent-failure-log.md`**（SRE Incident Log 风格，字段含 Observation / Agent Diagnosis / Actual Cause / Error Type / Preventive Rule，形成可复用 Agent Failure Dataset）；③ 限制 ADR 体积：未来细节迁 ADR-0022/0023/0024（Owner Accepted 后排期）；④ **新增 D7 Human Override Principle（人类最终裁决）**——核心命题 "Observed Reality > Agent Inference"，AI 推理 vs 物理现实冲突时，以 Human 在物理环境验证结果为准。顶层原则从 v1.3「防止 AI 在不确定环境下进行不可逆操作」升级为「**AI 在工程系统中必须保持能力、权限、认知三边界一致 + 物理现实高于抽象推理**」。

---

## 版本修订记录

- **v1.4（2026-08-01，四轮评审后微调 + 新增 D7）**：① D6.3 升级条件"两证据+可复现+Human确认 三全满足"过严，会导致 Agent 过度保守（删除临时文件也要三签字不现实）。改为 **R0-R3 风险分级**：R0 可逆操作（git status/diff/查看）AI 自主 / R1 低风险修改（普通代码/测试/文档）走标准流程 / R2 高风险操作（reset --hard/删除文件/DB 迁移/CI 权限修改）需"证据+验证" / R3 不可逆操作（force push/history rewrite/生产资源删除）需"两独立证据+可复现+Human批准 三全满足"。仅 R3 触发 D5/D6 完整升级链；② `docs/audit/git-failure-log.md` 泛化为 **`docs/audit/agent-failure-log.md`**（SRE Incident Log 风格，字段扩为 Observation / Agent Diagnosis / Actual Cause / Error Type / Preventive Rule 五字段，长期形成 Agent Failure Dataset，跨工程领域可复用）；③ 限制 ADR 体积：Owner Accepted 后，未来细节（Git 完整性 / AI 操作权限 / AI 诊断可靠性）迁 ADR-0022/0023/0024；④ **新增 D7 Human Override Principle**——核心命题 "Observed Reality > Agent Inference"，AI 推理 vs 物理现实冲突时，以 Human 在物理环境验证结果为准。**顶层原则升级为"AI 在工程系统中必须保持能力、权限、认知三边界一致 + 物理现实高于抽象推理"**。
- **v1.3（2026-08-01，三轮评审后新增 D6）**：v1.2 解决了"AI 能不能做"（D5 权限边界），但未解决"AI 敢不敢判断"——AI 在 Git 操作失败时容易把 L0/L1 瞬时错误（Windows 文件锁 / Defender 扫描 / IDE 占用 / 文件索引器）误判为 L2/L3 永久损坏（missing blob / ref 失稳），启动 commit-tree / update-ref / 改 `.git/*` 等不可逆操作，把 10 分钟的瞬时问题升级为架构级事故。**新增 D6 AI 故障归因协议（AI Failure Attribution Protocol）**：四层模型（L0 瞬时环境错误 / L1 工作区状态错误 / L2 Git 对象/引用错误 / L3 仓库结构损坏）+ Lock Failure 三阶段处理规则 + 单次失败不得触发不可逆操作的硬约束（必须两独立证据 + 可复现 + Human 确认）+ Failure Evidence Log（`docs/audit/git-failure-log.md`）兜底。**ADR 核心从"防止 AI 破坏 Git"提升为"防止 AI 在不确定环境下进行不可逆操作"**——D5 是权限边界，D6 是认知边界，两者结合方完整。
- **v1.2（2026-08-01，二轮评审后修订）**：① D5.2 hook 拦截方案**不可行**——Git commit 对象不存储来源（`commit-tree` 与 `git commit` 字节级无差异），v1.1 的 `git log -p | grep` 方案作废。改 Agent/Shell/CI 三层防御（Layer 1 Agent 命令拦截 + Layer 2 Git wrapper 脚本 + Layer 3 CI 异常检测）；② D5.1 黑名单过严——`git replace`（高级调试）与 `git filter-repo --dry-run`（预览工具）从黑名单降到灰名单。判定原则："能改写已发布历史"的命令，**带 dry-run 预览**→ 灰名单，**直接执行改写**→ 黑名单；③ D1.3 cherry-pick 串链归档**破坏证据**——cherry-pick 改 SHA/parent/历史结构，原始对象反而丢失。改 `git update-ref refs/archive/orphan-<date>/<sha>` ref 保活归档（SHA 与 parent 链字节级一致）；④ D2 根因从"确定"改为"最可能多因素叠加"——Defender / SearchIndexer / OneDrive / IDE 文件监听 / WSL 双重访问 / NTFS 文件锁 多个参与者均未排除；⑤ D3 Hard Rule 增加 **Candidate 临时状态**——规则新增到测试落地有时间差，期间的规则入 `§6.0 Rule Candidates`（Pending automation），测试落地后转正入 §6.1 Hard Rule。
- **v1.1（2026-08-01，Owner 评审后修订）**：① D2.1 packed-refs 措辞纠正——仅作"减少 loose ref 操作频率"的缓解措施，不作稳定性方案（根因是 Windows 文件锁 + `.git` 内部写竞争，packed-refs 不解决且会引入新单点 `packed-refs` 写入）；② D1.4 `Require linear history` 降级为 Optional（squash merge 已天然线性，强制反而增加 rebase 负担）；③ D1.3 dangling commit 改 `archive/orphan-<date>` 链式分支而非 tag（tag 会污染 `git tag` 输出）；④ D1 验证目标改为"无 missing object"而非"fsck 全净"（dangling commit 在 rebase 后是正常的，不应消除）；⑤ D3 机器化覆盖率 80%→**100%**（11 条 Hard Rule 必须全测；不可测的降级为 Guideline，不再叫 Hard Rule）；⑥ **新增 D5 AI Git 操作权限模型**（划出 AI 禁止动作清单 `git init` / `update-ref` / `commit-tree` / force push / 改 `.git/*` 内部文件）；⑦ PR 顺序从"A 文档→B 冻结→C 归档"调整为"**A ADR 接受→B 立即止血（GC 冻结+危险命令拦截+归档备份）→C 远程保护→D 物理审计→E 治理同步→F 机器化守门**"——先止血再整理文档。
- **v1.0（2026-08-01）**：初版。回应项目审计中"治理形式过度、治理实质失稳"的核心发现；提出 4 个 Decisions（D1 物理完整性 / D2 Ref 稳定性 / D3 Hard Rules 机器化 / D4 单一真相源）。

---

## 背景

### 触发本 ADR 的事件

2026-08-01 项目审计（会话内）发现仓库存在 **3 个相互独立但相互放大** 的不健康状态：

1. **物理对象层不完整**：`git fsck` 报告 main 历史中至少 2 个 missing blob（[AGENTS.md §12.1](../../AGENTS.md) 自承），且 24+ dangling commit 与 1 个 dangling tree 处于未归档状态。
2. **本地 ref 存储失稳**：`.git/refs/remotes/` 为空；`docs/sync-progress` 分支无任何 commit 树；AGENTS.md §12.2 描述的"用 `commit-tree` + `GIT_INDEX_FILE` 绕开 `git commit`" workaround 被工程化地接受。
3. **治理形式与治理实质脱节**：AGENTS.md §6.1 列出 11 条 Hard Rules，经审计盘点仅 4 条有对应机器检查（`provider_uniqueness_test.dart` / `message_friendly_test.dart` / `file_size_test.dart` / `file_access_test.dart`），**机器化覆盖率约 36%**。

### 现有约束

- [AGENTS.md §6.1](../../AGENTS.md) Hard Rules（11 条）——治理规范存在但机器化不完整
- [GIT_POLICY.md](../../.agent/GIT_POLICY.md) §0-5 治理四层闭环（Branch / CI Gate / Golden / Agent Policy）——框架存在但 Golden 层与 Agent Policy 层的"机器执行"部分有缺口
- [ADR-0006](./0006-ci-github-actions.md) CI 平台已锁 ——本 ADR 复用 GitHub Actions，不引入新 CI 平台
- [ROADMAP.md Phase 0](../ROADMAP.md) 已完成（README 自述）/ Phase 1 已完成（AGENTS.md §10 自述）——治理目标**在文档口径上已成立**，但实际仓库对象层有缺陷
- 当前未启用 `develop` 分支（AGENTS.md §5.2 计划启用但未执行），保持 main + feat/* + PR 模式

### 根因分析（避免错配优先级）

审计初稿把"missing blob / dangling commit / ref 失稳"三者并列。
**经校正后**，三者应分层处理：

| 层 | 现象 | 根因 | 优先级 |
|----|------|------|--------|
| 环境层 | `refs/remotes/` 为空、loose ref 频繁丢失 | Windows + Git Bash 文件锁 + loose ref 存储格式 | P1（高频复发，但不影响单次 PR） |
| 协议层 | missing blob、dangling commit | force-push + squash + rebase 后失保护的产物 | P0（历史不可信） |
| 治理层 | Hard Rules 机器化覆盖率 36% | 规范以文档形式沉淀、缺乏 Rule→Test→Gate 流水线 | P1（影响可持续性） |

**关键判断**：本 ADR 解决 **协议层 + 治理层**；环境层问题另起 `docs/environment/WINDOWS_BASH.md` 文档化，不混入本 ADR（避免 PR scope 膨胀）。

---

## 决策

### D1. 协议层：仓库物理完整性（Immediate，P0）

#### D1.1 冻结 GC 防二次丢失

```bash
# 一次性，本仓库 --local 范围
git config --local gc.auto 0
git config --local maintenance.auto false
```

**解冻条件（必须全部满足）**：
1. D1.2 的 missing blob 评估完成（无论 fix 或 archive）
2. D1.3 的 dangling commit 归档完成
3. 归档分支 `archive/orphan-<date>` 已 push 到 origin

**回滚**：`git config --local --unset gc.auto && git config --local --unset maintenance.auto`（由 Human Owner 执行）

#### D1.2 评估 missing blob 对当前 main 的影响

**步骤**：
1. `git fsck --no-progress --unreachable --dangling` 列出全部 orphan
2. 已知 SHA 列表（AGENTS.md §12.1 自承）：
   - `3298c833beccf2a6f211f3dc65b2a8ad70e89723`（editor_tokens.dart）
   - `23a03e1918205d2b6bb8fb4dc311813564378b66`（document_list_screen.dart）
3. 对每个 SHA 执行：
   ```bash
   git ls-tree -r main | grep <sha>      # main HEAD 树是否引用
   git log --all --pretty=%H | while read c; do
     git ls-tree -r $c | grep <sha>
   done | sort -u                           # 历史中哪些 commit 引用
   ```
4. **判定**：
   - 仅旧 commit 引用 → 记录到 `docs/audit/MISSING_BLOBS.md`，**不修复历史**（rewrite 会扩大不确定性）
   - main HEAD 引用 → 必须恢复（占位文件 + `git replace` 或在 archive 分支重建 self-consistent base）

#### D1.3 Dangling commit 归档（v1.2 重构）

> **v1.2 重大修正**：v1.1 写的「把 dangling commit 串成链」**会破坏证据**。cherry-pick 会改 SHA、改 parent、改历史结构——这正是我们想保留的原始证据。归档的目的不是「重构历史」而是「保存证据」。

**严禁 v1.1 的 `cherry-pick 串成链` 模式**：会改 commit SHA、parent 与历史结构，**原始对象反而丢失**。

**v1.2 正确做法：ref 保活归档**——直接在原始 commit 上加命名 ref，不动对象本身：

```bash
# 1. 建归档根分支（仅作命名空间载体，不承载 cherry-pick）
git branch archive/orphan-20260801 origin/main

# 2. 对每个需要保留的 dangling commit 建独立 ref（不链不 pick）
git update-ref refs/archive/orphan-20260801/<short-sha> <dangling-sha>
# 3. 列出归档
git for-each-ref refs/archive/
```

**归档目录结构**：

```
refs/archive/
└── orphan-20260801/
    ├── a1b2c3d   ← 指向原始 dangling commit A，SHA 不变
    ├── e4f5g6h   ← 指向原始 dangling commit B，SHA 不变
    └── i7j8k9l   ← 指向原始 dangling commit C，SHA 不变
```

**链式 vs ref 保活对比**：

| 维度 | v1.1 链式（cherry-pick） | v1.2 ref 保活 |
|------|------------------------|--------------|
| 原始 SHA | ❌ 改变 | ✅ 保留 |
| parent 链 | ❌ 重写 | ✅ 保留 |
| `git show` 内容 | ⚠️ 与原始略不同（tree 一致，metadata 变） | ✅ 字节级一致 |
| 审计价值 | ⚠️ "重构后的近似" | ✅ "原始证据" |
| 操作复杂度 | 高（要处理冲突） | 低（一条 `update-ref`） |
| 风险 | 中（重写过程可能引入新 dangling） | 低（仅加 ref，不改 object） |

**分类处理**：

| 类型 | 识别特征 | 处理 |
|------|---------|------|
| 临时 fix CI 残留 | 标题含 `fix(test)` / `fix(ci)`，无功能改动 | **不归档**，留 dangling 自然 GC（GC 冻结后默认保留 90 天） |
| 含实质代码改动 | diff > 50 行非测试文件 | 加 `refs/archive/orphan-20260801/<sha>` ref，不 cherry-pick；人工 review 决定是否 cherry-pick 到新分支 |
| 实验性 / 试错 | commit message 含 "WIP" / "experiment" / "draft" | ref 保活，作为历史教训 |
| Merge 冲突解产物 | 父 commit 链断裂 | ref 保活，作为 PR 冲突案例 |

**禁止**：
- 直接 `git gc --prune=now` 清理所有 dangling 对象
- 用 tag 形式保留（长期污染 `git tag` 输出）
- cherry-pick / rebase / reset 重写归档对象（破坏证据）

#### D1.4 GitHub Branch Protection 启用

由 Human Owner 在 GitHub UI 配置（不在本仓库文件可声明）：

- `main`（**Required**）：
  - ✅ Require status checks：`preflight` + `analyze` + `test` + `build`
  - ✅ Do not allow force pushes
  - ✅ Do not allow deletions
  - ✅ Restrict who can push：仅 Owner
- `main`（**Optional**，按团队流程选择）：
  - ◻ Require linear history —— **仅在团队使用 merge commit 时需要**。若团队已采用 "PR → squash merge → main"（推荐），squash merge 本身已天然线性，**不需要开启**此选项。强制 linear 反而增加 rebase 负担并降低历史可读性。
  - ◻ Require signed commits
  - ◻ Include administrators

**核心保护（不可妥协）**：
1. 任何 commit 进入 main 前必须经 status check 验证
2. 任何 force push 到 main 都被拒
3. main 永远不可被删除

**linear history 不是保护历史完整性的核心**——保护核心是「未经 CI 验证的代码不能进 main」「不能通过 force push 改写 main」「main 不能被删」。Linear history 只是历史线性度偏好，**不应误读为"安全机制"**。

- `feat/*`：
  - 无强制要求（PR 流程已守门）

**机器化替代**：如 branch protection UI 配置困难，可临时用 `server-side pre-receive` hook（`.git/hooks/pre-receive` 在 server 端）替代，但需 Human Owner 在 server 落地。

### D2. 环境层：Ref 存储稳定性（Medium-term，P1）

> 严格意义上属环境层问题，**不在本 ADR 强制范围**。本节仅作设计指引，详细落地见 `docs/environment/WINDOWS_BASH.md`（未来文档，本 ADR 起草后由独立 PR 建立）。
>
> **根因（v1.2 降低确定性）**：当前证据最符合 **Windows 文件系统锁竞争**，但**尚未证明单一进程根因**。可能参与者包括：
> - Windows Defender 实时扫描（写入触发 scan-on-write）
> - Windows Search Indexer（后台索引文件变动）
> - OneDrive / 云同步软件（D 盘被纳入同步路径时）
> - IDE / 编辑器 文件监听（VS Code / Cursor 等）
> - WSL 与 Windows 双重访问（Git Bash + WSL `/mnt/d` 共写 `.git/`）
> - 真正的 NTFS 文件锁与 Git Bash msys 进程
>
> **审计判断**：本环境最可能为**多因素叠加**，**不是**单一根因。v1.1 写成"Windows 文件锁 + Git Bash 写竞争"过于确定，**实际未排除其他参与者**。本 ADR 措辞承诺：根因待 PR-D 物理审计时进一步收窄。
>
> **任何缓解措施都不替代根因诊断**。本节所有方案仅作"降低失败概率"，**不声称根治**。

#### D2.1 缓解：减少 loose ref 操作频率（packed-refs 仅作缓解，非稳定性方案）

```bash
git pack-refs --all
```

**实际效果**：
- 减少 `refs/heads/xxx` / `refs/tags/xxx` / `refs/remotes/origin/xxx` 这些 loose ref 文件的创建/删除次数
- 把 ref 存储从"每次操作一个文件"变成"一个 packed-refs 文件批量管理"

**不解决的问题**：
- `HEAD` / `index` / `logs/HEAD` / `objects/*` 仍受 Windows 文件锁影响
- `packed-refs` 文件本身成为**新的单点写入文件**——若被锁住，所有 ref 操作失败
- loose ref 的"小步写"问题变成 packed-refs 的"整块写"问题，未必更优

**ADR 措辞承诺**：本 ADR **不声称** `git pack-refs --all` 之后 Git 环境已稳定；它只是降低失败概率的缓解措施，**不替代根因解决方案**。任何后续文档若将本条标榜为"稳定性方案"，属误读。

#### D2.2 中期：fetch refspec 锁定

```bash
git config --local remote.origin.fetch \
  "+refs/heads/*:refs/remotes/origin/*"
git config --local fetch.prune true
git config --local remote.origin.prune true
```

**预期效果**：保证 `refs/remotes/origin/*` 不会被错误清理。

#### D2.3 长期：worktree + 隔离测试环境（不属本 ADR）

未来 Phase 4+ 评估 `git worktree` + 容器化环境隔离，避免本机环境对仓库操作的污染。

### D3. 治理层：Hard Rules 机器化（Long-term，P1）

**核心原则（v1.1 升级）**：

> **Hard Rule = 100% 可执行规则 = 100% 必须有 Test。**
> **无法自动化测试的，从 Hard Rule 降级为 Guideline，不再叫 Hard Rule。**
> 11 条 Hard Rule 数量不多，不留 20% 模糊地带给 AI 踩。

**目标覆盖率 100%**（v1.0 写 80% 是 v1.1 修订项）：AGENTS.md §6.1 任何 Hard Rule 必须存在至少 1 个对应自动化测试，否则**自动降级**为 Guideline（移出 §6.1，放 §11 Guideline 章节）。

#### D3.1 已有守门（继承）

| AGENTS.md §6.1 条款 | 守门测试 |
|---|---|
| 6.1.2 禁止重复 Provider | `test/architecture/provider_uniqueness_test.dart` |
| 6.1.3 禁止 UI 暴露 error detail | `test/error/message_friendly_test.dart` |
| 6.1.4 禁止 print() | 需补 grep 守门（见 D3.2） |
| 1.2 文件 400 行上限 | `test/architecture/file_size_test.dart` |
| 6.1.1 core 不反向 import presentation | 部分（仅 file_access_test 守 file I/O，未覆盖 import 方向） |

#### D3.2 待补守门（按优先级）

| 优先级 | AGENTS.md 条款 | 待补测试 / 工具 | 入口 |
|---|---|---|---|
| P0 | 1.1 分层依赖方向（core 不反向） | `test/architecture/import_direction_test.dart` | `preflight.sh` |
| P0 | 6.1.4 禁止 print() | `tool/lint/no_print_call.dart` | `preflight.sh` |
| P0 | 6.2.1-3 禁止提交 build/ .dart_tool/ pubspec.lock | `test/architecture/forbid_tracked_paths_test.dart` | `preflight.sh` |
| P1 | 6.1.6 setState 之外改 Provider state | `test/architecture/state_guard_test.dart` | `preflight.sh` |
| P1 | 6.1.7 禁止新增全局静态状态 | `tool/lint/static_state_scan.dart` | `preflight.sh` |
| P2 | 2.1 命名规范 | `tool/lint/naming_lint.dart` | `preflight.sh` |
| P2 | 2.4 文件头必含 dartdoc | `tool/lint/file_header_test.dart` | `preflight.sh` |
| P2 | 6.2.7 PowerShell 不直调 flutter.bat | **降级为 Guideline**（不可跨平台机器测试）→ 移出 §6.1 → 入新 §11 | — |

**目标覆盖率 100%**：D3.2 全部落地后，AGENTS.md §6.1 的 11 条 Hard Rules 全部有机器守门。
**降级机制**：D3.2 评估后判定「不可测试」的条款（如「禁止在 PowerShell 中直调 flutter.bat」属环境规则，机器难以跨平台判断），从 §6.1 移出，迁入 AGENTS.md 新增 §11 Guideline 章节。**禁止留在 §6.1 但不配 Test**——这是 v1.0 的灰色地带，必须清理。

**入口**：
- `flutter_app/test/architecture/` 放置所有 `test/...test.dart`（沿用现有目录）
- `flutter_app/tool/lint/` 放置 Dart / Python 脚本（与 `preflight.sh` 同级）
- `preflight.sh` 顺序调用：`flutter analyze --fatal-warnings` → `flutter test test/architecture/` → `dart run tool/lint/*.dart`

#### D3.3 Hard Rule 生命周期：Candidate → Hard Rule（v1.2 增加）

> **v1.2 修正**：v1.1 写「Hard Rule 100% 必有 Test」原则正确，但忽略「规则新增到测试落地的时间差」——这段时间新规则没有 Test，留在 §6.1 违反"100% 必有 Test"原则；移到 Guideline 又过早妥协。**引入 Candidate 临时状态**。

```
                  ┌─ 起草（写入 §6.0 Rule Candidates）
                  │   Status: Pending automation
                  │
Proposal ────────→│
                  │
                  ├─ 测试落地（CI 通过 preflight）
                  │   Status: Active
                  ↓
              Hard Rule（移入 §6.1）
```

**§6.0 Rule Candidates 段位（PR-F 落地）**：

```markdown
## §6.0 Rule Candidates（Pending automation）

新增规则先入本节，**不享受 §6.1 Hard Rule 强制力**。测试落地后（CI preflight 通过）转入 §6.1。

### Candidate-001（2026-08-XX 起草）

> 禁止新增全局静态状态

- 起草人：XXX
- 起草原因：YYY
- 关联测试：tool/lint/static_state_scan.dart（PR-H 落地）
- 预计落地：2026-XX-XX

### Candidate-002 ...

**Candidate 规则对 Agent 的效力**：
- 任务描述未明确说"违反 Candidate 规则"时，Agent 默认遵守（视为软规则）
- Owner 可在任务里显式说"暂时忽略 Candidate-001"（明确豁免）
- 90 天未落地的 Candidate 自动归档到 `docs/audit/candidate-archive.md`
```

**为什么 90 天**：90 天足够写一个测试 + 跑通 CI；超 90 天说明规则不重要或无人负责。归档而非删除——保留教训。

#### D3.4 Rule → Test → Gate 流水线

任何新 Hard Rule 必须按此流水线落地：

```
Rule（写入 AGENTS.md §6.1）
  ↓
Test（在 test/architecture/ 或 tool/lint/ 落地）
  ↓
Gate（preflight.sh 调通 + CI required check 启用）
  ↓
Owner 签字 → Accepted
```

**禁止**：只写 Rule 不写 Test。**禁止**：Rule 与 Test 由同一次 PR 提交（拆 PR，Rule PR 必含 Test 引用 + Gate 启用 commit）。

### D4. 治理层：单一真相源（Governance）

#### D4.1 阶段定位

**唯一真相源**：`ROADMAP.md`
**引用方**：`README.md` / `AGENTS.md` §0 / `CRITICAL_REVIEW.md` 顶部 / `GIT_POLICY.md` §0

**修正当前口径不一致**：
- README 顶部"Phase 0：工程化基础建设" → 改为引用 `ROADMAP.md` 当前阶段
- AGENTS.md §0 已写「Phase 2 编辑模型」 → 与 ROADMAP Phase 2 一致 ✓
- CRITICAL_REVIEW.md 顶部需新增"最近更新阶段"段

#### D4.2 ADR 编号纪律

补 [AGENTS.md §7](../ARCHITECTURE.md)：

```
ADR 编号规则：
1. NNNN 从 0001 严格递增。
2. 任何跳号必须在跳号位创建 NNNN-SKIPPED.md。
3. 不得重用已 Accepted / Superseded 的编号。
4. SKIPPED 文件状态固定为 Closed，永久保留。
```

#### D4.3 阶段口径同步 PR

任何 PR 触及：
- `ROADMAP.md` 当前阶段
- `AGENTS.md` §0 阶段定位
- `README.md` 当前阶段

**必须同时**同步其他 2 份文档的对应段，并在 PR 描述中列明「阶段口径同步」。

### D5. 协议层：AI Git 操作权限模型（v1.1 新增，P0）

> **v1.1 重大遗漏补救**。本 ADR 之前未明确 AI 协作者对 Git 内部操作的权限边界。事故回溯（AGENTS.md §12 + 2026-08-01 审计）显示：当前 missing blob、ref 失稳、dangling commit **全部源自 AI 越过 Git 安全抽象直接修改 `.git/` 内部**（`commit-tree` / `GIT_INDEX_FILE` / `update-ref` / 手写 ref）。换机器可解环境问题，**不解决 AI 权限边界 = 下一台机器还会复发**。本节是 D1-D4 的前置条件。

#### D5.1 三档命令清单（v1.2 分级细化）

| 档位 | 命令 | AI 默认 | 备注 |
|------|------|---------|------|
| 🟢 允许（无确认） | `git status` / `git diff` / `git log` / `git show` / `git blame` / `git ls-files` / `git ls-tree` / `git fsck --no-progress`（只读） | ✅ 默认 | |
| 🟢 允许（标准流程） | `git add` / `git commit` / `git checkout`（feature 分支）/ `git fetch` / `git pull --ff-only` / `git branch -d`（已合并分支） | ✅ 默认 | 必须走 `preflight.sh` 守门 |
| 🟡 需 Owner 确认 | `git push` / `git merge` / `git rebase` / `git reset` / `git cherry-pick` / `git tag` / `git stash` / **`git replace`** / **`git filter-branch`** / **`git filter-repo`**（带 `--dry-run` 除外） | ⚠️ 任务描述含"经 Owner 授权"才执行 | 输出需附"已获 Owner 授权"声明 |
| 🔴 禁止（即使 Owner 显式要求也需 ADR 流程） | `git init` / `git commit-tree` / `git update-ref` / `git symbolic-ref` / `git hash-object -w` 写对象 / `git push --force` / `git push --force-with-lease` / 任何手写 `printf > .git/refs/*` / 直接修改 `.git/*` 任何文件 / **`git filter-repo` 不带 `--dry-run`** | ❌ 禁止 | 必须在独立 ADR 提议并 Owner 签字后才能改写 |

**v1.2 分级理由**：
- `git replace`：高级调试工具（修复历史 parent / 调试 missing blob），**v1.1 错把它列入黑名单过严**。改为灰名单：Owner 审批后可用，但仍不应用于 PR 流程中（CI 看不到 replace 效果，会破历史完整性）。
- `git filter-branch` / `git filter-repo`：**双重身份**——带 `--dry-run` 是分析工具（灰名单）；不带 `--dry-run` 是历史重写（黑名单，v1.1 误统一列黑名单）。**默认 v1.2 拆为：filter-repo 不带 dry-run 入黑名单；带 dry-run 入灰名单**。
- **判断原则**：所有「能改写已发布历史」的命令，**带 dry-run 预览**→ 灰名单；**直接执行改写**→ 黑名单。

#### D5.2 物理拦截层（PR-B 落地，v1.2 重构）

> **v1.2 重大修正**：v1.1 写的 `.githooks/pre-push-bash` 用 `git log -p | grep` 检测 commit 历史里的 `commit-tree` 等命令字串——**这个方案不可行**。Git commit 对象只保存 `tree / parent / author / committer / message`，**不保存这个 commit 是 `git commit` 还是 `commit-tree` 创建的**。`commit-tree` 产生的 commit 在历史里与 `git commit` 产生的 commit 字节级无法区分。
>
> v1.2 改用**多层防御**，每层在合适位置兜底：

**Layer 1：Agent/Shell 层（最关键）**

在 Agent 包装层（Claude Code / Cursor / 自研 wrapper）做 **命令级拦截**：

```python
# 伪代码示意，落地在 agent 工具层
BEFORE_COMMAND_EXECUTE = {
    "block": [
        r"\bgit\s+init\b",
        r"\bgit\s+commit-tree\b",
        r"\bgit\s+update-ref\b",
        r"\bgit\s+symbolic-ref\b",
        r"\bgit\s+hash-object\s+(-w|--write)\b",
        r"\bgit\s+filter-(branch|repo)\b",
        r"\bgit\s+push\s+.*(--force|--force-with-lease|-f)\b",
        r">\s*\.git/refs/",  # 直接写 ref 文件
    ],
    "require_approval": [
        r"\bgit\s+replace\b",  # 见 D5.1 灰名单：高级调试，需审批
        r"\bgit\s+filter-(branch|repo)\b(?!.*--dry-run)",  # 历史重写需审批
    ],
}

def before_command_execute(cmd):
    for pattern in BEFORE_COMMAND_EXECUTE["block"]:
        if re.search(pattern, cmd):
            raise PermissionError(f"D5.2 拦截：{cmd} 命中黑名单")
    for pattern in BEFORE_COMMAND_EXECUTE["require_approval"]:
        if re.search(pattern, cmd):
            request_human_approval(cmd)
```

**Layer 2：Git wrapper（系统级，最稳）**

在 `$PATH` 靠前位置放 `~/bin/git` 替代真实 git：

```bash
#!/usr/bin/env bash
# ~/bin/git
case "$*" in
  *commit-tree*|*update-ref*|*symbolic-ref*|*filter-branch*|*filter-repo*)
    echo "ERROR: D5.2 wrapper 拦截：'$*' 命中黑名单" >&2
    echo "需独立 ADR 提议并 Owner 签字" >&2
    exit 128
    ;;
  *push*--force*|*push*--force-with-lease*|*push*-f*)
    echo "ERROR: D5.2 wrapper 拦截：force push" >&2
    exit 128
    ;;
esac
exec /usr/bin/git "$@"
```

**Layer 3：CI 端异常检测（兜底）**

CI 在 `git fsck` 之后加异常检测（**只能检测结果，不能检测行为**）：

```bash
# .github/workflows/ci.yml
- name: Detect suspicious objects
  run: |
    # 检测有 commit 但 parent 链异常（如有 commit 但无对应 merge commit）
    git rev-list --all --max-count=1000 | while read sha; do
      author=$(git log -1 --format=%an $sha)
      # 异常特征：作者为 bot 且 parent 数 > 1（commit-tree 倾向）
      if [[ "$author" == "Agent" ]] && [[ $(git cat-file -p $sha | grep -c "^parent ") -gt 1 ]]; then
        echo "WARNING: $sha 多 parent 来自 bot，疑似 commit-tree 产物"
      fi
    done
```

**为什么必须 Layer 1+2+3 三层**：Layer 1 在 Agent 层最准但依赖 Agent 实现；Layer 2 在 Shell 层最稳但有 PATH 覆盖风险；Layer 3 在 CI 端只兜结果不兜行为。**三层任何一层能拦到即可**，互为冗余。

#### D5.2.1 为什么不能拦截 commit 历史（保留 v1.1 错误记录）

供 v1.2 评审追溯：v1.1 误以为 `git log -p` 能看到原始命令，**实际 Git 不存储此信息**。本节保留作为"曾尝试的方案及失败原因"，避免未来评审者重复发明。

#### D5.3 AGENTS.md §6.4 表扩展（PR-F 落地）

在 [AGENTS.md §6.4](../../AGENTS.md) AI/Human 提交分工表下方追加：

```
### Git 命令白/灰/黑名单（v1.1 起严格执行）

🟢 白名单：read-only + 标准 commit/push 流程，无需授权
🟡 灰名单：需 Owner 在任务描述中显式声明"已授权 X" 才能执行
🔴 黑名单：即使 Owner 显式要求也需先走独立 ADR 流程（防绕过 §6.4 审批）

完整清单见 ADR-0021 §D5.1。
物理拦截由 .githooks/pre-push-bash 强制。
```

#### D5.4 为什么 D5 比 D2 更重要

| 维度 | D2（环境层） | D5（权限层） |
|------|-------------|------------|
| 触发条件 | Windows + Git Bash 文件锁 | 任何环境，AI 越权操作 |
| 复发条件 | 换 Linux/macOS 即解 | 换机器仍复发，**只换 Owner 审核习惯才解** |
| 修复路径 | 一次性换工具链 | 长期习惯 + ADR 门槛 |
| 紧急度 | P1 | **P0** |

**结论**：D2 是「症状缓解」；D5 是「病灶切除」。本 ADR v1.1 把 D5 列为 P0，与 D1.1 冻结 GC 同优先级。

### D6. 认知层：AI 故障归因协议（AI Failure Attribution Protocol，v1.3 新增，P0）

> **v1.3 关键补充**：v1.2 解决了"AI 能不能做"（D5 权限边界），但**未解决"AI 敢不敢判断"**——这是更深层的安全漏洞。
>
> **事故链还原**（2026-08-01 审计推断）：
> ```
> 真实根因：Windows 文件锁（10 分钟问题）
>       ↓
> AI 误判为：Git ref 永久损坏
>       ↓
> 启动不可逆修复：commit-tree → update-ref → 手写 ref → 改 .git/*
>       ↓
> 真实后果：missing blob + 24+ dangling commit（架构级事故）
> ```
>
> **核心命题**：AI 在不确定环境下不应进行不可逆操作。**D5 是权限边界，D6 是认知边界，两者结合方完整。**

#### D6.1 故障归因四层模型

| 层级 | 类型 | 示例 | AI 默认动作 | 是否允许不可逆操作 |
|------|------|------|------------|------------------|
| **L0** | 瞬时环境错误 | 文件锁、Defender 扫描、IDE 占用、SearchIndexer | **重试 + 等待** | ❌ 禁止 |
| **L1** | 工作区状态错误 | 未保存修改、index 异常、untracked 冲突 | **检查状态 + 提示用户** | ❌ 禁止 |
| **L2** | Git 对象/引用错误 | missing blob、broken ref、dangling commit | **只读审计 + 报告** | ❌ 禁止（必须 D6.3 升级条件） |
| **L3** | 仓库结构损坏 | refs 不可恢复丢失、objects 库被破坏 | **请求 Human 介入** | ❌ 禁止（Human 签字后才能动） |

**核心规则**：**任何层级下 AI 都不得自行执行不可逆操作**。L0/L1 由 Agent 等环境；L2/L3 升级到 Human。

#### D6.2 Lock Failure 三阶段处理（强制性）

当 AI 遇到：
```
fatal: Unable to create '.git/index.lock': File exists
fatal: cannot lock ref 'refs/heads/...'
Permission denied
```

**AI 不得直接判断**：`Git repository corrupted` / `Need to fix Git` / `commit-tree workaround`

**必须执行三阶段**：

**第一阶段：环境诊断**（必须先做，不能跳过）
```bash
# 1. 确认 lock 文件状态
ls -la .git/*.lock 2>&1

# 2. 确认是否有其他 git 进程
ps aux | grep -i git | grep -v grep

# 3. 确认是否有 IDE / 编辑器持有
# （Windows: tasklist | findstr -i code）
# （macOS: pgrep -fl "Code|VSCode|Cursor"）

# 4. 确认磁盘空间
df -h .git
```

**判定标准**：
- `.git/*.lock` 存在且时间戳 < 5 分钟 → **L0 瞬时锁**，等 10 秒重试
- `.git/*.lock` 存在且时间戳 > 30 分钟 → **L0 残留锁**（上一次崩溃），需 Human 确认删除
- `ps` / `tasklist` 看到其他 git/IDE 进程 → **L0 进程占用**，等进程结束
- 全部检查无异常但仍失败 → 升级到 L1 检查工作区

**第二阶段：等待 + 重试**（首次失败后）
```
第一次失败
   ↓
等待 10 秒（sleep 10）
   ↓
再次执行同一命令
   ↓
成功 → 记录 L0 到 D6.4 故障日志，继续原任务
   ↓
仍失败 → 升级到第三阶段
```

**第三阶段：人工验证**（必须 Human 参与才能升 L1+）

AI 输出：
> "我执行 `git commit` 失败，错误信息是 `<error>`。我已执行 L0 三阶段诊断（lock / 进程 / 磁盘），结果如下：<结果>。请您在终端手动执行一次同一命令：\n\n  `<command>`\n\n如果您的执行成功 → 归因为 Agent 执行环境问题（可能是 Agent 进程被 Defender 扫描阻断等），请告诉我您成功了，我会重新执行并加 retry 逻辑。\n\n如果您的执行也失败 → 升级到 L1/L2，需要进一步诊断。"

**判定原则**：
- `Agent 失败 + Human 成功` → L0（环境对 Agent 局部而非 Git 状态问题）
- `Agent 失败 + Human 失败` → L1/L2（真实状态问题，升级处理）

#### D6.3 风险分级与不可逆操作升级条件（v1.4 改为 R0-R3 分级）

> **v1.4 修正**：v1.3 写"两证据+可复现+Human确认 三全满足"对所有不可逆操作过于严苛——删除临时文件不必三签字，会导致 Agent 过度保守。**改为风险分级**，仅 R3 触发完整升级链。

**风险分级表**（与 D5.1 命令清单正交：风险分的是"操作后果可逆性"，命令分的是"命令是否在白名单"）：

| 风险级 | 类型 | 示例 | 升级条件 | AI 默认行为 |
|--------|------|------|---------|------------|
| **R0** | 可逆操作 | `git status` / `git diff` / 查看日志 / 重新执行测试 | 无 | **AI 自主**（无需任何确认） |
| **R1** | 低风险修改 | 修改普通代码 / 新增测试 / 更新文档 / 新增文件 | 走 D3 守门（preflight.sh）+ 常规 lint | **AI 自主**（标准 PR 流程） |
| **R2** | 高风险操作 | `git reset --hard` / 删除文件 / 修改数据库 / 修改 CI 权限 / `git rebase` 已有 commit / 大规模重构 | **1 个独立证据 + 1 次复现**（无需 Human 确认，但日志必填） | **AI 可执行但需日志** |
| **R3** | 不可逆操作 | `git push --force` / `filter-repo` / `filter-branch` / `replace` / 删除生产资源 / `commit-tree` / 改 `.git/*` / 任何已发布历史重写 | **2 个独立证据 + 可复现 + Human 确认 三全满足** | **AI 不得执行，必须 Human 签字** |

**与 v1.3 三全满足的对比**：

| 操作 | v1.3 升级 | v1.4 升级 | 变化 |
|------|----------|----------|------|
| `git status` | 三全满足 | R0 无需确认 | 解放 |
| 修改测试文件 | 三全满足 | R1 走 preflight | 解放 |
| `git reset --hard` | 三全满足 | R2 1 证据+1 复现 | 适当放松 |
| `git push --force` | 三全满足 | R3 三全满足 | 不变 |
| `git filter-repo` | 三全满足 | R3 三全满足 | 不变 |

**核心精神保留**：**R3 不可逆操作必须有 Human 签字**——这是 v1.3 的核心命题，v1.4 不削弱。

**操作分类原则**（新增，便于 R2/R3 边界判定）：

- **可逆 = 5 分钟内能用 git / 文件系统恢复**（如 reset --soft、git revert、文件 rm 后从 index 找回）
- **不可逆 = 5 分钟内不能恢复**（如 force push 后远端历史丢失、filter-repo 后 commit 改写、生产资源删除）
- **边界模糊时升级**：R2 → R3 边界（如 `git rebase` 在 main 分支 → 视为 R3；在私有 feat 分支 → 视为 R2）

**D6.3 与 D5 关系更新**：
- D5.1 是**命令层**黑/灰/绿名单（静态）
- D6.3 是**风险层**分级（动态，与上下文相关）
- 双重检查：命令在 D5.1 绿名单 + 风险为 R0/R1 → AI 自主；任一升级 → 按更高风险处理

#### D6.4 Failure Evidence Log（v1.4 泛化）

> **v1.4 修正**：原 `docs/audit/git-failure-log.md` 范围过窄。**泛化为 `docs/audit/agent-failure-log.md`**，对齐 SRE Incident Log 风格，未来可承载数据库失败 / 云资源失败 / CI 失败等跨工程领域记录。

**文件路径**：`docs/audit/agent-failure-log.md`

**五字段格式**（比 v1.3 的七字段更精简且可复用）：

| 字段 | 含义 | 示例 |
|------|------|------|
| **Observation** | Agent 看到了什么 | `git commit` 报 `index.lock exists` |
| **Agent Diagnosis** | AI 当时的判断 | "仓库损坏，需重置 index" |
| **Actual Cause** | 真实原因 | Windows Defender 实时扫描触发文件锁 |
| **Error Type** | 误判类型 | L0 → L2 错误升级 |
| **Preventive Rule** | 新增 / 强化规则 | "Lock failure 默认 L0 等 10s 重试" |

**记录触发条件**（v1.4 收紧）：
- 任何 R2/R3 操作执行前后必须记录（即使成功）
- Agent 任何误判案例（事后发现判断错误）
- Agent 主动升级 L0 → L1+ 但实际是 L0 的案例

**长期价值**（v1.4 强调的 "Agent Failure Dataset"）：

> 6 个月后 `agent-failure-log.md` 累计 50+ 案例 → 评审时一眼看出：
> - 80% 是 L0 误判为 L2 → 收紧 D6.1 默认升级倾向
> - 15% 是 R2 操作未记录 → 强化 D6.4 记录强制
> - 5% 是 R3 绕过 Human 签字 → 需升级 D5 拦截
>
> 这是**用真实数据校准 D5/D6 阈值**的依据，远比拍脑袋设参数更可靠。

#### D6.5 不确定性管理（核心命题）

> **v1.3 核心命题（写入 ADR 顶层原则）**：
>
> **防止 AI 在不确定环境下进行不可逆操作。**
>
> 不确定性的 3 个来源：
> 1. **环境层**（D2）：Windows 文件锁 / Defender / IDE / 文件索引 / WSL 桥接——**瞬时、局部、可重试**
> 2. **协议层**（D1/D5）：missing blob / 错误 ref / 命令越权——**持久、结构化、需审计**
> 3. **认知层**（D6）：错误归因 / 故障分类 / 升级决策——**判断偏差、累积放大、需约束**
>
> **AI 的天然倾向**：把 L0 误判为 L2 → 启动不可逆操作 → 把瞬时问题升级为永久损坏。
>
> **ADR-0021 的防护**：
> - D5 拦"能不能做"（命令层）
> - D6.3 拦"该不该做"（状态层）
> - D6.4 留证据（认知层）
>
> 三层组合，**让不可逆操作变得昂贵**——必须两层证据 + 一次人工签字。

#### D6.6 与 D5 的关系

| 维度 | D5（权限边界） | D6（认知边界） |
|------|---------------|---------------|
| 解决什么 | "AI 能不能修改 .git/*" | "AI 敢不敢在不确定时修改 .git/*" |
| 拦截位置 | 命令执行前 | 错误归因时 |
| 静态/动态 | 静态（命令清单） | 动态（升级条件） |
| 触发条件 | 任何 `commit-tree` 调用都拦 | 仅在错误已发生且被误判时拦 |
| 与 D5.1 关系 | 黑/灰/绿三档 | 在灰档解锁前增加证据门槛 |

**两层缺一不可**：D5 单独存在时，AI 可"合理怀疑"后强行走灰名单（带审批）；D6 单独存在时，AI 可在绿名单执行不可逆操作（因为不违规）。**两层组合后**：D5 阻断大部分危险命令，D6 阻断"看似合理但归因错误"导致的越界。

### D7. 元层：人类最终裁决（Human Override Principle，v1.4 新增，P0）

> **v1.4 顶层补充**：D5 解决"AI 有没有资格做"，D6 解决"AI 知不知道自己在做什么"。**但两者都没解决：当 AI 推理与物理现实冲突时，谁说了算？**
>
> 答案必须明确：**物理现实高于抽象推理，Human 在物理环境验证后的结果高于 Agent 在抽象环境中的推理。**

#### D7.1 核心命题

```
Observed Reality  >  Agent Inference
   ↑
   │
Human 在物理环境
手动验证的结果
```

**不能反过来**：
- ❌ "我（Agent）已经诊断过了，结论是 X，您不需要再试" → **禁止**（剥夺 Human 验证权）
- ❌ "错误日志清楚显示是 Y，结论明确" → **禁止**（把"推理确定性"等同于"物理事实"）
- ❌ "时间紧迫，请您直接批准" → **禁止**（用紧迫感绕过 Human 验证）

#### D7.2 物理现实与抽象推理的典型冲突

| Agent 推理 | Human 物理验证结果 | 结论 |
|-----------|------------------|------|
| "仓库损坏，需重建" | Human 手动 commit 成功 | **物理现实推翻推理**，按 L0 处理 |
| "Defender 是 anti-virus 问题，与我无关" | Human 关闭 Defender 后仍失败 | **推理正确**，升级到 L1+ 处理 |
| "AI 已分析过日志，无需重现" | Human 重现出相同错误 | **推理可保留**，但 Human 验证仍优先 |
| "AGENTS.md §X 写得清楚，按规定执行" | Human 说"那条规则过期了，按新规" | **Human 上下文优先于规则** |

#### D7.3 三原则

**原则 1（物理优先）**：任何 Git / DB / 系统操作，**Human 在物理环境手动执行的结果**是 ground truth。Agent 推理（包括日志分析、文档查阅、模式匹配）永远不能"覆盖"这个结果。

**原则 2（不可替代）**：Agent **不得**说"我已分析完毕，无需您手动验证"或类似表达。
- 不可逆操作（R3）必须 Human 手动验证后才能让 Agent 执行
- 高风险操作（R2）建议 Human 手动验证，但可不强制
- 即使 Agent 已 100% 确信，仍需保留 Human 验证选项（"请您在终端试一次"）

**原则 3（反驳权）**：当 Human 的物理验证结果与 Agent 推理矛盾时：
- Agent **不得**坚持原推理
- Agent **必须**承认"Human 物理验证推翻了我的推理"，并立即按 Human 结果重置诊断
- Agent 可在 D6.4 故障日志中保留原推理供复盘，但**不能影响当前决策**

#### D7.4 真实事故还原（v1.3 隐藏层）

v1.3 复盘了事故链：

```
Windows 文件锁（10 分钟问题）
    ↓
AI 误判为永久损坏
    ↓
commit-tree / update-ref workaround
    ↓
missing blob（架构级事故）
```

**但 v1.3 漏了关键一步**：在 AI 启动 commit-tree 之前，**如果 Human 说"我手动 commit 成功了"**，AI 就应该立即停止误判链路。

事故的根因不是"AI 做了 commit-tree"，而是 **"AI 在做 commit-tree 前没有请求 Human 物理验证"**。D7 拦的就是这个"未请求"——D6.3 升级条件是"被动要求 Human 确认"，D7 是"**主动要求 Human 物理验证**"。

#### D7.5 与 D5/D6 的关系

| 维度 | D5 | D6 | D7 |
|------|----|----|----|
| 层级 | 协议层 | 认知层 | 元层 |
| 解决什么 | "能不能做" | "该不该做" | "谁说了算" |
| 决策权归属 | 命令清单 | 升级条件 | **物理现实 / Human 验证** |
| 与 Agent 关系 | 静态约束 | 动态约束 | 终极约束 |

**D7 是 D5/D6 的仲裁者**：
- D5/D6 都可能误判（如"log 显示是损坏"是 D6 误判）
- D7 在两者冲突时启用——以 Human 物理验证为准
- D5/D6 越严，D7 越少触发；D5/D6 越松，D7 越频繁仲裁
- 理想状态：D5/D6 大部分时间足够，**D7 偶发仲裁，但不缺席**

#### D7.6 在 D6.2 Lock Failure 中的应用

D6.2 三阶段处理的第三阶段"人工验证"就是 D7 的具体应用：

> "请您在终端手动执行一次同一命令。"

**这是 D7.1 物理优先原则在 D6 中的强制要求**——不是"建议"，是 D7 + D6 共同强制的硬流程。**v1.3 写"升级到第三阶段"语气偏软，v1.4 应明确：第三阶段是 D7 强制要求，不存在"跳过 Human 验证"路径**。

---

## 后果

### 正面后果

1. **仓库物理状态可被审计**：D1.2 + D1.3 完成后，`git fsck` 无 missing object（dangling 可存在但归档覆盖）；D1.4 + D5 启用 branch protection + 命令拦截后 future-proof。
2. **治理强度回落到与代码量匹配**：D3.2 落地后 Hard Rules 机器化覆盖率 36% → **100%**（不可测的降 Guideline 移出 §6.1），形式治理转实质治理。
3. **AI 能力/权限/认知三边界一致**：D5 权限边界 + D6 认知边界 + D7 元层仲裁——三层正交，**缺一不可**。
4. **AI 不会过度保守**：D6.3 风险分级（R0-R3）避免 v1.3 "三全满足"导致的 Agent 瘫痪——R0/R1 操作 AI 自主，R3 仍需 Human 签字，**升级精神保留**。
5. **物理现实 > Agent 推理**：D7 明确当 AI 推理与 Human 物理验证矛盾时，**Human 验证为准**——避免 v1.3 漏掉的"AI 在做不可逆操作前未请求 Human 物理验证"环节。
6. **Agent Failure Dataset 长期校准**：D6.4 泛化为 `agent-failure-log.md` 后，6 个月数据可反哺校准 D5/D6 阈值——**用真实数据代替拍脑袋**。
7. **文档/工具/规范三者口径一致**：D4 单一真相源 + 编号纪律 + 阶段同步 PR 兜底。
8. **审计本身可被引用**：本 ADR 引用 2026-08-01 审计报告，建立"问题 → ADR → 修复"的可追溯链。

### 负面后果 / 代价

1. **短期 PR 数量增加**：D1 + D3.2 至少需要 5-6 个独立 PR 落地（拆分原则见 D3.4）。
2. **CI 时间可能增长**：`test/architecture/` 全跑 + `tool/lint/*.dart` 估算 +30s~2min，需评估。
3. **本 ADR 不解决环境层问题**：Windows + Git Bash 文件锁需独立 ADR 或文档化，否则 ref 失稳仍会复发。
4. **AGENTS.md §12 拆分工作**：环境 workaround（§12.1-§12.4）需迁出 AGENTS.md 到 `docs/environment/WINDOWS_BASH.md`，属后续 PR 范围。

### 风险

| 风险 | 触发条件 | 缓解 |
|------|---------|------|
| D1.1 GC 冻结被遗忘 | Owner 长期不归档 dangling commit | 在 D1.1 写入 cron / reminder |
| D3.2 测试落地拖延 | Agent 收到多个 P0 任务时跳过 | ADR-0021 复审时纳入 ROADMAP Phase 2.5 |
| D4 单一真相源失效 | 文档作者不读 ROADMAP 直接改 README | PR 模板新增"是否触及阶段定位"勾选项 |
| **D6 AI 故障误判** | **AI 把 L0 错误升级为 L2 修复，触发 commit-tree 等不可逆操作** | **D6.3 风险分级 + D6.4 故障日志 + D7 物理优先原则** |
| **D7 Human Override 被绕过** | **AI 跳过 Human 物理验证，自行推理后执行 R3 操作** | **D7.3 反驳权硬约束 + D6.2 第三阶段强制** |
| 本 ADR 自 commit | Agent 误解 §6.4 授权范围 | 本 ADR 在 Approved 状态前由 Owner 持有 commit 权限 |

---

## 验证计划

### D1 验证

> **验证目标调整（v1.1 修正）**：原 v1.0 写"`git fsck` 干净"过强。**dangling commit 不是错误**——rebase / `git reset --soft` / `git commit --amend` 之后正常 Git 仓库也会有 dangling object。盲目追求 fsck 全净会反过来限制合法工作流。

**正确目标（D1 全部完成后应满足）**：
- ✅ `git fsck --no-progress` 输出中 **无 `missing` 关键字**
- ✅ 所有 `dangling` object 可被合理 commit 链或已分类归档
- ✅ 无「无法解释的 unreachable object」（即归档分支上未声明的孤儿）

**显式 NOT 目标**：
- ❌ 不追求 `git fsck` 零 dangling object
- ❌ 不定期 `git gc --prune=now` 清空（与 D1.1 GC 冻结冲突）

**具体清单**：
- [ ] D1.1：`.git/config` 含 `gc.auto=0` + `maintenance.auto=false`
- [ ] D1.2：`docs/audit/MISSING_BLOBS.md` 已建立，2 个 SHA 各自判定状态已记录（仅旧 commit 引用 vs main HEAD 引用）
- [ ] D1.3：`archive/orphan-20260801` 分支已 push 到 origin；inventory 文件归档；未保留的 dangling commit 经 Owner 批准后**允许被自然 GC**
- [ ] D1.4：GitHub `main` branch protection 至少启用 status checks + no force push + no deletion 三项；linear history 按团队流程可选
- [ ] `git fsck --no-progress` 输出无 `missing` 行（dangling 可存在但须归档覆盖）

### D3 验证
- [ ] D3.1：5 条已有守门测试在 CI 中通过
- [ ] D3.2：8 条新守门按 P0/P1/P2 优先级落地；`preflight.sh` 顺序调通

### D4 验证
- [ ] D4.1：README / AGENTS.md / CRITICAL_REVIEW.md / GIT_POLICY.md 阶段段全部引用 ROADMAP
- [ ] D4.2：AGENTS.md §7 编号规则补全
- [ ] D4.3：PR 模板含"阶段口径同步"勾选项

---

## 实施拆解（建议 PR 顺序，v1.1 调整）

> **v1.1 调整原 v1.0 的"先文档后冻结"顺序**。新原则：**先止血，再整理文档，最后做机器守门**。
> 理由：当前仓库 ref 失稳 + missing blob 风险下，每多一个 PR 提交 / force-push 都在放大风险面；先把 GC 冻结、危险命令拦截、远程保护这三道闸口打上，再做物理审计与治理同步。

1. **PR-A（Owner 自提交）**：本 ADR 走 Accepted 流程
2. **PR-B（Owner + Agent，紧急止血，24 小时内）**：
   - D1.1 冻结 GC（`git config --local gc.auto 0`）
   - **D5.2 Layer 2 Git wrapper**（`~/bin/git` 拦截命令字符串）
   - **D6.4 新建 `docs/audit/agent-failure-log.md`**（v1.4 泛化；原 `git-failure-log.md` 不再建）
   - **D5.3 同步在 AGENTS.md §6.4 表下方加 D5.1 三档清单说明**（让 Agent 立即看到）
   - **D6 同步在 AGENTS.md §9.1「接到任务时的标准流程」前加 D6.2 Lock Failure 三阶段处理 + D6.3 R0-R3 风险分级 + D7.1 物理优先原则**（让 Agent 在执行 Git 操作前先看到认知 + 元层约束）
   - **D5.2 暂时跳过 Layer 1/3**（Agent/Shell/CI 三层防御的其余两层，留 PR-F 落地）
   - **D7.3 反驳权写入 AGENTS.md §6.4**："Agent 不得坚持原推理，必须承认 Human 物理验证"
   - **全量打包备份**：把 `.git/objects` 当前内容 `tar` 归档到 `docs/audit/snapshots/pre-adr-0021-<date>.tar`（仅本仓库内，作为 snapshot；不替代远程备份）
3. **PR-C（Owner 独立操作，PR-B 之后）**：D1.4 GitHub branch protection UI 配置（status checks + no force push + no deletion）
4. **PR-D（Agent 起草 / Owner 合并）**：D1.2 missing blob 评估 + D1.3 dangling commit 归档（`archive/orphan-<date>` 链式分支，**非 tag**）+ `docs/audit/MISSING_BLOBS.md` 建立
5. **PR-E（Agent 起草 / Owner 合并）**：D4.1 阶段口径同步 + D4.2 编号纪律 + D4.3 PR 模板 + 补 0010-SKIPPED.md（已物理落地）
6. **PR-F（Agent 起草 / Owner 合并）**：D5.3 在 AGENTS.md §6.4 表下方新增「AI Git 命令白/灰/黑名单」段（基于 PR-B 的 hook 拦截）
7. **PR-G+（按优先级排期）**：D3.2 P0 三条守门测试（import_direction / no_print / forbid_tracked_paths）
8. **PR-H+（Phase 2.5 排期）**：D3.2 P1/P2 守门

**顺序不可乱**：A→B 必连（A 是 B 的合规依据）；B→C 必连（无远程保护，止血不彻底）；C→D 必连（远程保护是物理审计的 baseline）。E/F 可与 D 并行但不得超前。G+ 全部依赖 A-F 落地。

每个 PR 独立可合并。

**D6/D7 配套行动项**（散落在各 PR）：
- PR-B：D6.4 `agent-failure-log.md` 模板 + AGENTS.md §9.1 前置 D6.2/D6.3/D7.1 段
- PR-D：D6.4 故障日志正式启用，AI 遇到 Git 错误必须记录
- PR-F：D6.3 R0-R3 风险分级 + D7.3 反驳权写入 AGENTS.md §6.1 Hard Rule，配 D3.2 P0 守门
- PR-后续：未来细节（Git 完整性 / AI 操作权限 / AI 诊断可靠性）迁 ADR-0022/0023/0024（Owner Accepted 后排期）

---

## 参考文档

- [AGENTS.md](../../AGENTS.md) §6.1 Hard Rules / §6.4 AI/Human 提交分工 / §11 CI 高频失败模式 / §12 Git 硬伤绕过
- [GIT_POLICY.md](../../.agent/GIT_POLICY.md) §0-5 四层治理闭环
- [ADR-0006 CI 选型 GitHub Actions](./0006-ci-github-actions.md)
- [ROADMAP.md](../ROADMAP.md) Phase 0-4
- 2026-08-01 项目规范与开发进度审计报告（会话内产出）

---

**本 ADR 由 AI Agent 起草（2026-08-01），v1.4 状态 Proposed；按 AGENTS.md §6.4 属架构决策类文件，Human Owner 评审签字 → Accepted。**
