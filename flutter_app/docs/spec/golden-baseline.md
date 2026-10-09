# Golden 基线策略：以 CI Linux 为准

> 归属 issue：[#335](https://github.com/Thy985/Tafcm/issues/335)。
> 结论一句话：**golden 基线以 CI（ubuntu-24.04）为权威；Windows 本地 golden 比对失败是环境性噪声，不代表视觉回归。**

---

## 1. 规则

| 环境 | 角色 | 结论判定 |
|------|------|---------|
| CI（`ubuntu-24.04`，Flutter 3.44.6，`Golden (compare)` job） | **权威基线** | 唯一能判定视觉回归的地方 |
| Windows 本地开发机 | 开发参考 | golden 小 diff **不构成失败**，不得据此判定回归 |

基线 PNG 位于 `flutter_app/test/golden/golden/`。所有 golden 测试文件都带
`@Tags(['golden'])`（library 级），因此：

```bash
# Windows 本地跑测试，跳过 golden（推荐日常用）
cd flutter_app && flutter test --exclude-tags golden

# 只跑 golden（本地比对，结果仅供参考）
cd flutter_app && flutter test --tags golden

# 重生成基线（必须在 Linux 上做，否则会把 Windows 光栅化结果写进权威基线）
cd flutter_app && flutter test --tags golden --update-goldens
```

CI 的 `Golden (compare)` job 只在 Linux 上跑，本地行为与 CI 天然解耦。

---

## 2. 为什么 Windows 本地会 diff

`test/golden/golden_helpers.dart` 已做跨平台固定：`locale=en_US`、
`textScaleFactor=1.0`、固定 viewport（800×1200）、`loadAppFonts()` 显式加载
打包字体 NotoSerifSC / NotoSansSC。即便如此，Windows 与 Linux 在
**Skia 文本光栅化的亚像素层**仍不完全一致——这是引擎层差异，helper 无法消除。

#335 的实测证据（同一份代码、同一台 Windows 主机）：

- 全量 `flutter test` 三轮结果 **-30 / -29 / -28**：三轮失败数不同，本身就是
  环境抖动的直接证据（真实视觉回归不会自己变来变去）。
- 28 个唯一失败**全部**是 `test/golden/` 下的像素比对，diff **均 < 1%**。
  抽样：`file_manager_dark.png` 0.26%（11062px）、
  `editor_shell_full_page_light_textscale_1_3.png` 0.75%（32594px）。
- 同一批 commit 在 CI（ubuntu-24.04）上 `Golden (compare)` 全部 success，
  最近 6 次 main 流水线（`37905808326` / `37798704940` / `37792934903` /
  `37783202514` / `37448039152` / `37438812612`）均为 completed/success。
  即：**同一代码 CI 全绿 + Windows 本地全红（但 < 1%）** → 环境差异，非回归。

---

## 3. 如何判断一次 golden 失败是真回归还是环境噪声

1. **先看 CI**：同一 commit 的 `Golden (compare)` job 绿 → 环境噪声，按本文档
   处置（本地 skip 或忽略）。
2. **CI 同挂** → 才是真视觉回归，另立修复单，并检查是否触碰了
   design tokens / 字体 / 布局。
3. **判断 diff 量级**：本地 diff < 1% 且 CI 绿 → 亚像素噪声；
   若 CI 上也出现大面积变化（布局错位、整块位移）才是回归。
4. 关联历史：[#233](https://github.com/Thy985/Tafcm/issues/233)
   记录过 golden job 持续失败 + `failures/` 产物被入库，已关闭；本条是其
   「本地开发机」侧的复现，归属以本文件为准。

---

## 4. 遗留

`AGENTS.md §13.2` 目前写的是「见 `flutter_app/test/golden/failures/` 目录，
已登记 skip」。实际该目录当前为空，`@Tags(['golden'])` 的
`--exclude-tags golden` 才是可用的跳过机制。§13.2 属架构决策类文件
（AGENTS.md §6.4），需 Human Owner 授权后单独修正——已随本 PR 在
issue #335 的评论中提出，不夹带进本 PR。
