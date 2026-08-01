/// 响应式断点体系（P1-1，UI_FIX_PLAN）。
///
/// 当前 app 此前无任何断点 / `LayoutBuilder` / `OrientationBuilder` 判断，
/// 侧栏 240 / 对话框 480 / 文件树 260 均为固定宽，375 窄屏会溢出。
/// 本文件集中定义断点常量 + 语义助手，作为全 app 响应式决策的唯一来源。
///
/// **断点语义**：
/// - [kTabletBreakpoint]：平板阈值（≥1024 视为平板，可考虑双栏 / 更宽松布局）。
/// - [kCompactBreakpoint]：紧凑阈值（<600 视为手机，侧栏/文件树须退化为抽屉覆盖层，
///   不得挤占编辑区）。取 600 而非 1024 的原因：golden 默认视口 800×1200 须保持"宽屏"
///   内联布局（与历史基线一致），故折叠阈值必须 < 800；600 与 workspace 的
///   `kMaxPageWidth=720` 同量级，手机/平板分界合理。
library;

import 'package:flutter/material.dart';

/// 平板断点（宽 ≥ 此值视为平板）。
const double kTabletBreakpoint = 1024;

/// 紧凑断点（宽 < 此值视为手机/紧凑屏，侧栏须退化为抽屉）。
const double kCompactBreakpoint = 600;

/// 是否为平板及以上宽度。
bool isTablet(BuildContext context) =>
    MediaQuery.of(context).size.width >= kTabletBreakpoint;

/// 是否为紧凑屏（手机）。文件树/侧栏在此宽度须退化为抽屉，不得内联占用编辑区。
bool isCompact(BuildContext context) =>
    MediaQuery.of(context).size.width < kCompactBreakpoint;
