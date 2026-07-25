# ADR-0016：文档仓储边界（Document Repository Boundary）

> **状态**：Proposed（随 Phase 3.4 Task Contract v1.1 提交，Human Owner 签字即 Accepted）
> **版本**：v1.0
> **起草日期**：2026-07-26
> **起草人**：AI Agent 起草，Human Owner 评审建议新增
> **关联文档**：
> - [Phase 3.4 Task Contract v1.1](../contracts/phase3.4-task-contract.md)
> - [ADR-0013 Autosave Architecture](./0013-autosave-architecture.md)（AutosaveService → `DocumentRepository.save()`）
> - [ADR-0014 Document Asset Management](./0014-document-asset-management.md)（`assets/` 布局）
> - [ADR-0003 Storage Single Source .md Files](./0003-storage-single-source-md-files.md)（单一真相源）
>
> **审批路径**：Human Owner 在第二轮评审中指出「谁负责打开 / 创建 / 删除 / 移动 / 加载 assets 尚未冻结，FileTree（3.4.2）会碰到」，建议新增本 ADR 定义仓储边界，供 FileTree / Autosave / Export 共用。

---

## 背景

### 当前状态
- [ADR-0013](./0013-autosave-architecture.md) 定义 `AutosaveService → DocumentRepository.save()`
- [ADR-0014](./0014-document-asset-management.md) 定义 `assets/` 物理布局

### 触发本 ADR 的事件
**文档生命周期的仓储边界**仍未冻结：谁负责 `open / create / delete / move / asset resolve`？FileTree（3.4.2）、Export（3.4.4）、Autosave（3.4.7）都会触碰这些操作。若不定案，三方各自实现文件 IO，很快出现路径解析 / 并发 / 引用不一致。

### 现有约束
- [ADR-0003](./0003-storage-single-source-md-files.md)：`.md` 为单一真相源。
- [Hard Rule 8](./0009-ui-architecture-design.md)：依赖方向单向，`panels/` / `chrome/` 不得反向被 `domain` / `services` 依赖。

---

## 决策

定义 **`DocumentRepository`** 为文档生命周期的唯一边界。

### 职责（Repository 负责）
| 操作 | 说明 |
|------|------|
| `load(path)` | 读取 `.md` → Document Model |
| `save(doc)` | Document Model → `.md`（Autosave / 手动保存共用，幂等） |
| `create(path)` | 新建文档 |
| `delete(path)` | 删除文档（含其 `assets/` 目录） |
| `move(src, dst)` | 移动 / 重命名文档（整目录，`assets/` 随行，相对路径不变） |
| `resolveAsset(docPath, assetName)` | 文档路径 → `assets/<name>` 文件 |

### 不负责（Repository 边界外）
- **UI navigation**：文件树导航属于 `panels/`，调 Repository 而非反向。
- **selection / focus**：编辑态属于 `EditorCoordinator`。
- **编辑操作**：经 Command Layer（ADR-0009）。

### 依赖方向（单向）
```
panels/ (FilePanel)  ─┐
chrome/ (Export)     ─┤→ DocumentRepository → File IO
services/ (Autosave) ─┘
```
`DocumentRepository` 不 import `panels/` / `chrome/` / `blocks/`（守 Hard Rule 8）。

---

## 与 ADR-0013 / 0014 的关系

- ADR-0013 的 `DocumentRepository.save()` 即本 ADR 的 `save`。
- ADR-0014 的 `assets/` 布局由本 ADR 的 `resolveAsset` / `move` / `delete` 统一管理。
- 三者共同构成「文档运行时（Document Runtime）」基础设施闭环：

```
              UI
               |
        ThemeExtension  (ADR-0015)
               |
         EditorCoordinator
               |  DirtyStateSource (ADR-0013)
               ▼
         AutosaveService (ADR-0013)
               |
         DocumentRepository (ADR-0016)
               |  assets/ (ADR-0014)
               ▼
          Document Folder (ADR-0003)
```

---

## 后果

### 正面后果
1. FileTree / Export / Autosave 复用同一仓储，无重复文件 IO。
2. 路径解析 / 并发 / asset 引用集中在 Repository，易于单测。
3. 未来云同步只需在 Repository 层加适配（`save` → `sync`），不波及 UI。

### 负面后果
1. 需先定义 Repository 接口，再让 3.4.2 / 3.4.4 / 3.4.7 接入（轻微排期前置，不阻塞）。

---

## 验证计划

- [ ] `DocumentRepository` 接口覆盖 `load / save / create / delete / move / resolveAsset`
- [ ] `move` 后 `assets/` 随行、相对路径不变（自包含）
- [ ] Repository 不反向依赖 `panels/` / `chrome/` / `blocks/`（grep 守门）

---

## 参考文档
- [Phase 3.4 Task Contract v1.1](../contracts/phase3.4-task-contract.md)
- [ADR-0013 Autosave Architecture](./0013-autosave-architecture.md)
- [ADR-0014 Document Asset Management](./0014-document-asset-management.md)
- [ADR-0003 Storage Single Source .md Files](./0003-storage-single-source-md-files.md)

---

**本 ADR 由 AI Agent 起草，v1.0，随 Phase 3.4 Task Contract v1.1 提交，Human Owner 签字即 Accepted。**
