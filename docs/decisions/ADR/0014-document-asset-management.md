# ADR-0014：文档资产管理（Document Asset Management）

> **状态**：Accepted（v1.2 修订随 Phase 3.4 Slice 4 评审，Human Owner 评审意见即授权）
> **版本**：v1.2
> **起草日期**：2026-07-26
> **起草人**：AI Agent 起草，Human Owner 评审决策
> **关联文档**：
> - [Phase 3.4 Task Contract v1.0](../../contracts/phase3.4-task-contract.md)（§3.4 / §9，3.4.9 图片插入）
> - [ADR-0003 Storage Single Source .md Files](./0003-storage-single-source-md-files.md)（单一真相源）
> - [ADR-0013 Autosave Architecture](./0013-autosave-architecture.md)（落盘路径共用）
>
> **审批路径**：Human Owner 在 Phase 3.4 契约评审中指出「图片资产生命周期必须设计，否则图片插入以后一定返工」，故独立成 ADR 冻结资源存储方式。

---

## 版本修订记录

- **v1.0（2026-07-26）**：初版，冻结图片 `assets/` 副本 + 相对路径 + 命名冻结 `img_<uuid>.png` + 块删除仅 reference removal。
- **v1.1（2026-07-26，评审补充）**：① 验证计划 `image001.png` 统一为 `img_<uuid>.png` 以匹配冻结命名（3 处）；② 负面后果「递增命名」改为 UUID 唯一性去重（与决策一致）；③ 新增 §操作级别澄清，明确块级 reference removal 与 ADR-0016 文档级 `delete(path)` 物理删除是不同操作者/级别。随 PR #68 提交，合并后 Proposed→Accepted。
- **v1.2（2026-07-26，Slice 4 实现评审，Human Owner 决策）**：命名策略从「UUID + 冻结 `.png`」**升级为「内容寻址 + 原格式保留」**：`img_<sha256 前 16 位>.<原扩展名>`。这是**架构决策**而非实现偏离——见 §命名策略（v1.2 决策）。同步新增格式白名单与拒绝规则、共享资产对删除语义的影响说明。

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
      └── img_a82f92cd91ab32ef.jpg
```

Markdown 源码：

```md
![](assets/img_a82f92cd91ab32ef.jpg)
```

### 命名策略（v1.2 决策：内容寻址 + 原格式保留）

**资产采用内容寻址命名：`img_<sha256 前 16 位>.<原扩展名>`。**

规则：
1. 文件名 = 图片字节内容的 sha256 hash 前 16 位（内容寻址，同 Git object / Docker layer digest 思路）；
2. **保留原始扩展名**（`.png` / `.jpg` / `.gif` / `.webp` / `.bmp`），不统一转 PNG；
3. 插入时按扩展名白名单校验，**不支持的格式拒绝导入**（抛用户可读错误）；
4. 单张体积上限 20MB（全量读内存 hash 的保护阈值）。

**为何放弃 v1.0 的 `img_<uuid>.png`（UUID + 冻结 PNG）**：

| 维度 | UUID + 冻结 PNG（v1.0） | 内容寻址 + 原格式（v1.2，采纳） |
|------|------------------------|-------------------------------|
| 去重 | 无——同一截图反复插入产生 N 份副本 | hash 相同天然去重，截图 / 公式图 / 教程文档重复率高的场景收益大 |
| 体积 | jpg→png 转换常见 3MB→15MB 膨胀 | 保留原格式，无膨胀 |
| 动画 | gif / webp 转 PNG 丢失动画 | 保留 |
| Phase 4 演进 | 同步需另建内容索引 | hash 即内容标识，云同步 / 增量同步 / 版本化直接可用 |
| 渲染成本 | 仅 PNG 分支 | Flutter `Image.file` 原生支持白名单内全部格式，成本≈0 |

**内容寻址的代价（已知并接受）**：
- **共享资产使删除更复杂**：多文档 / 多引用可能指向同一物理文件，删除不能直接删文件，需引用计数或 GC——本 ADR 的删除语义（块删除仅 reference removal + Phase 4 Asset GC）**本来就不做即时物理删除**，与内容寻址天然兼容，无额外代价。
- 文件名暴露内容指纹（sha256 前缀不可逆，接受）。

> **防架构漂移警示**：v1.0/v1.1 文本中的 `img_<uuid>.png` 命名与「扩展名冻结 PNG」已**废止**。后续任何 Agent / 开发者不得按旧版本把实现改回 UUID + PNG。

### 资源生命周期

| 阶段 | 行为 |
|------|------|
| **插入** | `file_picker` 选图 → 格式白名单校验 + 20MB 上限 → 复制到 `assets/` → **命名 `img_<sha256 前 16 位>.<原扩展名>`**（v1.2 内容寻址，同内容自动去重，避免多人 / 多设备同步时递增命名 `image001.png` 冲突）→ 插入相对路径 `ImageElement` |
| **删除（Phase 3.4）** | 块删除时**仅移除 Markdown 引用（reference removal）**，**不删除 `assets/` 物理文件**——① 用户删除后立即 undo 需能恢复，物理删除不可回退；② v1.2 内容寻址下资产可能被多处引用共享，即时物理删除需引用计数，统一交 Phase 4 GC |
| **孤立 asset GC（Phase 4）** | 物理文件清理推迟到 Phase 4 的 Asset Garbage Collector：扫描 `assets/` 中无引用的文件并删除（内容寻址下即孤立 hash 检测）；本期不实现 |
| **移动 / 重命名文档** | 整目录移动，`assets/` 随行，相对路径不变 → 自包含、可迁移 |

### 操作级别澄清（与 ADR-0016 联动，评审补充）

「删除」在本项目有两个**不同操作者 / 不同级别**，不可混淆：

| 级别 | 操作者 | 行为 | 出处 |
|------|--------|------|------|
| **块级删除（block-level）** | 用户在编辑器内删除含图片的块 | **仅移除 Markdown 引用（reference removal）**，不删 `assets/` 物理文件——保证 undo 可恢复 | 本 ADR §资源生命周期 / Phase 3.4 Contract §3.4 |
| **文档级删除（document-level）** | 用户在文件树 / 文件管理屏删除整个文档 | **物理删除整目录（含 `assets/`）**——`DocumentRepository.delete(path)`（ADR-0016） | ADR-0016 |

两者互不冲突：块级删除是「编辑态内的轻量撤销友好操作」，文档级删除是「资源回收」，由 `DocumentRepository` 统一负责物理 IO。块删除产生的孤立 asset 由 Phase 4 的 Asset GC 扫描清理（见本 ADR 删除策略），不在本期物理删除。

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
1. 文档体积随图片增长（可接受，移动端单文档规模有限；v1.2 内容寻址去重进一步缓解）。
2. 命名冲突由内容 hash 天然规避（同内容同名 = 去重复用；不同内容 sha256 前 16 位碰撞概率可忽略）。
3. 共享资产的物理删除需 Phase 4 GC 统一处理（见 §命名策略 代价说明）。

---

## 验证计划

### 单元
- [x] `file_picker` 选图 → `assets/img_<hash>.<ext>` 存在于文档目录（asset_service_test）
- [x] 重复插入同一图片 → 不重复复制（内容寻址去重，asset_service_test）
- [x] 相对路径生成正确（`assets/img_<hash>.<ext>`，非绝对路径）
- [x] 格式白名单外拒绝 / 源文件缺失 → `AssetImportException`（v1.2 新增）

### E2E（链 3 持久化强制，3.4.9 必须）
- [ ] 从相册插入图片 → 关 App → 重开 → 验证三项同时成立：
  1. markdown source 含 `![](assets/img_<hash>.<ext>)`
  2. 文件系统 `assets/img_<hash>.<ext>` 存在
  3. 渲染出该图片
- （仅「插入成功」不算完成，必须落盘 + 重开一致）

---

## 参考文档
- [Phase 3.4 Task Contract v1.0](../../contracts/phase3.4-task-contract.md)
- [ADR-0003 Storage Single Source .md Files](./0003-storage-single-source-md-files.md)
- [ADR-0013 Autosave Architecture](./0013-autosave-architecture.md)

---

**本 ADR 由 AI Agent 起草，v1.0，随 Phase 3.4 Task Contract v1.0 提交，Human Owner 签字即 Accepted。**
