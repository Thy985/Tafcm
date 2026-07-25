# ADR-0014：文档资产管理（Document Asset Management）

> **状态**：Proposed（随 Phase 3.4 Task Contract v1.0 提交，Human Owner 签字即 Accepted）
> **版本**：v1.0
> **起草日期**：2026-07-26
> **起草人**：AI Agent 起草，Human Owner 评审决策
> **关联文档**：
> - [Phase 3.4 Task Contract v1.0](../contracts/phase3.4-task-contract.md)（§3.4 / §9，3.4.9 图片插入）
> - [ADR-0003 Storage Single Source .md Files](./0003-storage-single-source-md-files.md)（单一真相源）
> - [ADR-0013 Autosave Architecture](./0013-autosave-architecture.md)（落盘路径共用）
>
> **审批路径**：Human Owner 在 Phase 3.4 契约评审中指出「图片资产生命周期必须设计，否则图片插入以后一定返工」，故独立成 ADR 冻结资源存储方式。

---

## 背景

### 触发本 ADR 的事件
Phase 3.4 引入 3.4.9 Markdown 图片插入（从相册选图）。早期契约仅写 `file_picker + ImageElement`，未定义图片**存储位置与生命周期**。存在两个隐含方案：

- **方案 A**：复制到文档目录 `assets/` 子文件夹，Markdown 用相对路径引用（文档自包含）
- **方案 B**：引用系统绝对路径（如 `C:/Users/a/photo.png`）

若不在本期定案，图片插入实现会各 PR 各做，未来跨设备 / 重装必然返工。

### 现有约束
- [ADR-0003](./0003-storage-single-source-md-files.md)：`.md` 为单一真相源，文档应自描述、可独立迁移。

---

## 决策

**采用方案 A：图片复制到文档目录的 `assets/` 子文件夹，Markdown 用相对路径引用。文档自包含。**

### 存储布局

```
document/
 ├── main.md
 └── assets/
      └── img_a82f3c.png
```

Markdown 源码：

```md
![](assets/img_a82f3c.png)
```

### 资源生命周期

| 阶段 | 行为 |
|------|------|
| **插入** | `file_picker` 选图 → 复制到 `assets/` → **命名冻结为 `img_<uuid>.png`**（UUID，避免多人 / 多设备同步时递增命名 `image001.png` 冲突）→ 插入相对路径 `ImageElement` |
| **删除（Phase 3.4）** | 块删除时**仅移除 Markdown 引用（reference removal）**，**不删除 `assets/` 物理文件**——用户删除后立即 undo 需能恢复，物理删除不可回退 |
| **孤立 asset GC（Phase 4）** | 物理文件清理推迟到 Phase 4 的 Asset Garbage Collector：扫描 `assets/` 中无引用的文件并删除；本期不实现 |
| **移动 / 重命名文档** | 整目录移动，`assets/` 随行，相对路径不变 → 自包含、可迁移 |

### 拒绝方案 B（系统绝对路径）
```md
![](C:/Users/a/photo.png)
```
**拒绝原因**：
1. 换设备 / 重装 App → 路径失效，图片丢失。
2. 破坏 [ADR-0003](./0003-storage-single-source-md-files.md) 单一真相源（`.md` 应自描述，不依赖外部绝对路径）。
3. 无法随文档打包 / 导出 / 同步。

### Out of Scope（明确不在此 ADR）
- **云存储图片**（对象存储直链）：未来接同步时再议，本期一律落本地 `assets/`。
- **图片压缩 / 格式转换**：可选优化，不在本期（插入原图即可）。
- **孤立 asset 物理删除**：本期不做（仅 reference removal），GC 留 Phase 4（见删除策略）。

---

## 后果

### 正面后果
1. **文档自包含**：`.md` + `assets/` 整体可复制 / 导出 / 同步，符合 ADR-0003。
2. **跨设备安全**：相对路径不依赖宿主文件系统布局。
3. **渲染稳定**：`ImageElement` 按相对路径 + 文档基准目录解析，重开一致。

### 负面后果
1. 文档体积随图片增长（可接受，移动端单文档规模有限）。
2. 复制去重需处理命名冲突（递增命名即可，无需 hash）。

---

## 验证计划

### 单元
- [ ] `file_picker` 选图 → `assets/image001.png` 存在于文档目录
- [ ] 重复插入同一图片 → 不重复复制（去重）
- [ ] 相对路径生成正确（`assets/image001.png`，非绝对路径）

### E2E（链 3 持久化强制，3.4.9 必须）
- [ ] 从相册插入图片 → 关 App → 重开 → 验证三项同时成立：
  1. markdown source 含 `![](assets/image001.png)`
  2. 文件系统 `assets/image001.png` 存在
  3. 渲染出该图片
- （仅「插入成功」不算完成，必须落盘 + 重开一致）

---

## 参考文档
- [Phase 3.4 Task Contract v1.0](../contracts/phase3.4-task-contract.md)
- [ADR-0003 Storage Single Source .md Files](./0003-storage-single-source-md-files.md)
- [ADR-0013 Autosave Architecture](./0013-autosave-architecture.md)

---

**本 ADR 由 AI Agent 起草，v1.0，随 Phase 3.4 Task Contract v1.0 提交，Human Owner 签字即 Accepted。**
