/// BaseBlockState 抽象基类：Block 组件双态切换共享样板。
///
/// 落地 Phase 3.1-A Task Contract §3.1.A.2（R4 评审反馈）。
/// 落地 Phase 3.2 Task Contract §3.0 方案 A（基类统一调度）：
/// - `build()` 由基类统一按 `currentMode` 分发到 `buildRenderContent` / `buildEditField`
/// - 子类只实现 `buildRenderContent`（render 态差异）+ 可选 `editFieldDecoration` / `editFieldStyle`
/// - 不再重写 `build()`（消除 40 行/Block 的分发样板）
///
/// **背景**：Phase 3.0 时 3 个 Block 组件（paragraph / heading / code）各自重复实现：
/// - `late final TextEditingController _textController`
/// - `late final FocusNode _focusNode`
/// - `initState` / `dispose` 中的 controller / focus 初始化与销毁
/// - `_onFocusChange` listener + `_commitSource` 共享逻辑
/// - `build()` 中的 `if (currentMode == RenderMode.editing) return _buildEditing();` 分发
///
/// **R4 抽象**（Phase 3.1-A）：把 controller / focus / commit 样板抽到基类。
/// **§3.0 方案 A**（Phase 3.2）：把 build() 分发也抽到基类,子类职责更聚焦。
///
/// **未来 BlockType 复用**（Math / Mermaid / Table / Quote / Image / Link）
/// 只需：
/// 1. `class MermaidBlock extends StatefulWidget`
/// 2. `class _MermaidBlockState extends BaseBlockState<MermaidBlock>`
/// 3. `@override Widget buildRenderContent(...)` 实现 render 差异
/// 4. 无需重复 controller / focus / commit / build 分发样板
///
/// **实现选择**：Flutter [State] 是 class，mixin-on-class 约束较多，
/// 因此选择抽象类继承而非 mixin 模式。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

import '../../core/editing/block_types.dart';
import '../../core/observability/models.dart' as obs;
import '../commands/commands.dart';
import '../editor/editor_coordinator.dart';
import '../editor/editor_intent.dart';
import '../editor/editor_scope.dart';
import '../states/block_view_state.dart';
import 'block_enter_intent_formatter.dart';
import 'input/input_handler.dart';

/// Block 组件状态抽象基类。
///
/// **职责**：
/// - 管理 [TextEditingController] / [FocusNode] 生命周期
/// - 监听 [FocusNode] 变化，触发 [UpdateBlockSourceCommand]
/// - 双态切换（render ↔ edit）通过基类 `build()` 统一分发
/// - 提供 [buildRenderContent] 抽象让子类实现 render 差异
///
/// **继承约束**：
/// - 子类必须实现 [buildRenderContent]（render 差异）
/// - 子类可选覆盖 [editFieldStyle] / [editFieldDecoration] / [editFieldMaxLines]
///   / [editFieldInputAction]（edit 态 TextField 配置）
/// - 子类可选覆盖 [onModeChanged]（监听模式变化）
/// - 子类**不应**重写 `build()`（已由基类统一调度）
abstract class BaseBlockState<T extends StatefulWidget> extends State<T> {
  /// Markdown 源文本控制器（共享样板）。
  late final TextEditingController textController;

  /// 焦点监听器（共享样板）。
  late final FocusNode focusNode;

  /// 当前 Block 所属的 [EditorCoordinator]（缓存，避免事件回调中调用 of(context)）。
  late EditorCoordinator _coordinator;

  /// 上次同步到 controller 的 source（R1 修复：检测外部 source 变化）。
  late String _lastSyncedSource;

  /// 标记当前是否正在本地 commit（R1 修复：区分本地输入与外部命令）。
  bool _isCommitting = false;

  /// 自动输入行为调度器（Phase 3.3 PR #3：自动配对 + 自动续列表）。
  ///
  /// 落地 Task Contract v1.1 §2.6：BaseBlockState 委托 InputHandler,
  /// 不直接实现配对 / 续行规则,避免 God Object 膨胀。
  late final InputHandler _inputHandler;

  /// 回车意图拦截器（Phase A：捕获软键盘插入的 `\n` → 派发 [EnterPressedIntent]）。
  ///
  late final TextInputFormatter _enterFormatter;

  /// 上一次 [TextEditingValue]（Phase 3.3 PR #3：自动配对/续列表的 oldValue 来源）。
  ///
  /// **为什么由 BaseBlockState 持有而非 InputHandler**：
  /// - InputHandler 设计为无状态（纯函数式调度,便于测试）
  /// - BaseBlockState 已管理 [textController] 生命周期,自然持有其历史值
  /// - 避免状态分散在 InputHandler + BaseBlockState 两处
  ///
  /// **重置时机**：进入 editing 模式时重置为当前 controller value（[didUpdateWidget]）。
  TextEditingValue? _previousTextValue;

  @override
  void initState() {
    super.initState();
    _coordinator = EditorScope.of(context, listen: false);
    textController = TextEditingController(text: _initialSource());
    _lastSyncedSource = textController.text;
    _previousTextValue = textController.value;
    focusNode = FocusNode();
    focusNode.addListener(_onFocusChange);
    textController.addListener(_onSelectionChanged);
    _inputHandler = InputHandler();
    _enterFormatter = EnterIntentFormatter(onEnter: _onEnterIntercepted);
  }

  // ============ Phase 3.3 PR #2B §2.7: selection 同步（节流）============

  /// 帧内节流标记（同一帧内多次 selection 变化只同步一次）。
  bool _selectionSyncScheduled = false;

  /// selection 变化回调：仅 focused 时同步,帧内节流。
  ///
  /// **节流策略**（§2.7）：
  /// 1. 仅 focused 时同步（非聚焦块的 selection 变化不进入全局状态）
  /// 2. 帧内节流：同一帧内多次 selection 变化只同步一次,
  ///    通过 [WidgetsBinding.instance.addPostFrameCallback] 合并
  void _onSelectionChanged() {
    if (!mounted || !isFocused) return; // 仅 focused 时同步
    if (_selectionSyncScheduled) return; // 帧内已调度,跳过
    _selectionSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionSyncScheduled = false;
      if (!mounted) return;
      final sel = textController.selection;
      final current = _coordinator.viewStateOf(blockId)?.selection;
      if (sel != current) {
        final state =
            _coordinator.viewStateOf(blockId) ?? BlockViewState(id: blockId);
        _coordinator.updateViewState(blockId, state.copyWith(selection: sel));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 用 listen: true 注册依赖,响应 EditorScope.coordinator 实例替换
    _coordinator = EditorScope.of(context);
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检测 mode 变化（RenderMode 切换时同步 controller 文本 + 焦点）
    if (currentMode != previousMode(oldWidget)) {
      // Phase 3.6.1 E2E 修复：从 editing 切到 rendered 时，在当前 mode 被
      // 覆盖前先 commit 当前编辑文本。否则 _onFocusChange 中的
      // `currentMode == RenderMode.editing` 检查会因 mode 已更新而跳过，
      // 导致编辑内容永远不被提交到 committed source。
      // 用 post-frame callback 避免 _commitSource 内部 notifyListeners()
      // 在 build 阶段被调用（否则 AnimatedBuilder 的 setState 会抛异常）。
      if (previousMode(oldWidget) == RenderMode.editing) {
        final text = textController.text;
        final id = blockId;
        final coord = _coordinator;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // P0 修复（CORE-010）：no-op guard，source 未变则不派发命令。
          // P0 修复后非 IME 输入已立即 commit，失焦时 domain source 已是最新；
          // 此处重复派发会产生空 Transaction 污染 undo 栈（Undo 弹空栈 → 无变化）。
          // IME 组合态未 commit 时 text != sourceOf(id)，仍会派发以提交 IME 输入。
          if (text == coord.sourceOf(id)) return;
          coord.handle(UpdateBlockSourceCommand(
            blockId: id,
            newSource: text,
          ));
        });
      }
      textController.text = _initialSource();
      _lastSyncedSource = textController.text;
      _syncSelectionFromViewState();
      // Phase 3.3 PR #3：进入 editing 时重置 oldValue（避免跨会话残留）
      _previousTextValue = textController.value;
      if (currentMode == RenderMode.editing) {
        // **IME 中断修复 2（2026-08-06）**：requestFocus 延后到下一帧。
        // SplitBlockCommand / MergeWithPreviousCommand 后，新块的
        // TextEditingController 才刚赋值 text、同步 selection。
        // 如果同步调用 requestFocus()，IME 会连接到"尚未完成文本同步"
        // 的 controller，产生 composing 区域混乱或直接断开。
        // 改为下一帧 requestFocus，先让 Flutter 完成 build + value 同步。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (currentMode == RenderMode.editing) {
            focusNode.requestFocus();
          }
        });
      }
      onModeChanged(previousMode(oldWidget));
    } else if (!_isCommitting) {
      // R1 修复：检测外部 source 变化（如 toolbar 命令修改了 Document）
      final newSource = _initialSource();
      if (newSource != _lastSyncedSource) {
        textController.text = newSource;
        _lastSyncedSource = newSource;
        // R2 修复：同步 selection（cursor 位置由 Coordinator 计算）
        _syncSelectionFromViewState();
        // 外部 source 变化后同步 oldValue（避免下次输入误判）
        _previousTextValue = textController.value;
      }
    }
    _isCommitting = false;
  }

  /// 从 [BlockViewState] 同步 selection 到 controller（R2 修复）。
  ///
  /// Coordinator 在 handle InsertText/WrapSelection 后会更新 viewState.selection,
  /// 此方法将其同步到 [TextEditingController.selection]。
  void _syncSelectionFromViewState() {
    final sel = _coordinator.viewStateOf(blockId)?.selection;
    if (sel != null) {
      // 外部 source 变化（如 undo/redo 回滚）后,旧 selection 可能越界 → 钳制到新文本长度,
      // 避免 TextSelection.collapsed(offset:N) 在更短文本上抛 invalid text selection。
      final len = textController.text.length;
      final base = sel.baseOffset.clamp(0, len);
      final extent = sel.extentOffset.clamp(0, len);
      textController.selection =
          TextSelection(baseOffset: base, extentOffset: extent);
    }
  }

  @override
  void dispose() {
    focusNode.removeListener(_onFocusChange);
    focusNode.dispose();
    textController.removeListener(_onSelectionChanged);
    textController.dispose();
    super.dispose();
  }

  /// **§3.0 方案 A 基类统一调度**：
  /// 按 [currentMode] 分发到 [buildRenderContent]（render 态）或
  /// [buildEditField]（edit 态）。子类不应重写此方法。
  @override
  Widget build(BuildContext context) {
    if (currentMode == RenderMode.editing) {
      return buildEditField(
        style: editFieldStyle,
        decoration: editFieldDecoration,
        maxLines: editFieldMaxLines,
        inputAction: editFieldInputAction,
        inputFormatters: [_enterFormatter],
      );
    }
    return buildRenderContent(context);
  }

  /// 焦点变化回调：edit → render 时 commit 修改。
  ///
  /// **R4 共享逻辑**：当 focusNode 失焦且当前处于 editing 模式,
  /// commit 当前 textController 文本并清除 focus。
  ///
  /// **IME 中断修复 1（2026-08-06）**：
  /// - 如果 `currentMode != RenderMode.editing`（说明 Coordinator 已经
  ///   通过 `focusOn(newId)` 把本块切回 rendered，例如 SplitBlockCommand
  ///   之后），不再调用 `_coordinator.clearFocus(blockId)`。否则会再次
  ///   notifyListeners 触发 rebuild，使本帧内 IME 又失去一次连接机会。
  ///   只保留 `_commitSource`，以提交未 commit 的 live 文本。
  void _onFocusChange() {
    if (!focusNode.hasFocus) {
      // 无论 mode 是否已被 Coordinator 切走，都尝试 commit 剩余 live 文本。
      // （SplitBlockCommand 前 flushLiveSource 已经对齐，此处多为 no-op；
      // 但外部点击失焦场景下 liveSource 还没对齐，必须走这里。）
      _commitSource();
      // 仅当逻辑模式仍为 editing 时通知 Coordinator 清焦点。
      // 若 mode 已经是 rendered，说明 Coordinator 在 focusOn(nextId)
      // 时已把本块切回渲染态，再次 clearFocus 会产生多余 notifyListeners
      // 打断新块 requestFocus 的 IME 连接。
      if (currentMode == RenderMode.editing) {
        _coordinator.clearFocus(blockId);
      }
    }
  }

  /// commit 当前 textController 文本到 [EditorCoordinator]。
  ///
  /// **R1 修复**：设置 [_isCommitting] 标志,防止 didUpdateWidget 把
  /// 本地输入误判为外部命令而反向同步 controller（导致光标跳位）。
  ///
  /// **P0 修复（CORE-006）**：增加 no-op guard，source 未变时跳过（防止空
  /// Transaction 入栈）。非 IME 输入现在每次按键都调用此方法立即 commit，
  /// 失焦时再次调用为 no-op。
  void _commitSource() {
    if (textController.text == _lastSyncedSource) return;
    _isCommitting = true;
    _lastSyncedSource = textController.text;
    _coordinator.handle(UpdateBlockSourceCommand(
      blockId: blockId,
      newSource: textController.text,
    ));
  }

  /// 当前 Block 所属的 [EditorCoordinator]（缓存,避免 of(context) 热点）。
  ///
  /// **修复 PR #1 review 反馈**：原实现每次调用都执行
  /// `EditorScope.of(context)`,在事件回调（[_onFocusChange] / [_commitSource]）
  /// 中会注册 InheritedWidget 依赖（Flutter 反模式）。
  /// 现改为返回 [_coordinator] 缓存值,由 [didChangeDependencies] 维护。
  EditorCoordinator get coordinator => _coordinator;

  /// 当前 Block 是否处于聚焦态（editing 模式）。
  ///
  /// 用于 [_onSelectionChanged] 节流判断：仅聚焦块同步 selection 到
  /// [CoordinatorState]（§2.7）。非聚焦块的 selection 变化不进入全局状态。
  bool get isFocused => currentMode == RenderMode.editing;

  /// 当前 Block 的 [BlockId]（子类必须实现，从 widget 拿）。
  BlockId get blockId;

  /// 当前 Block 的渲染模式（从 [BlockViewState] 拿，子类必须实现）。
  RenderMode get currentMode;

  /// 从 [oldWidget] 拿前一次的模式。
  ///
  /// **强制抽象**：子类必须实现，通常为 `previousMode(oldWidget) => oldWidget.state.mode`。
  /// 此为抽象方法以避免静默不生效（若默认返回 [currentMode]，模式切换检测
  /// `currentMode != previousMode(oldWidget)` 始终为 false，controller 同步 + 焦点
  /// 请求将无法触发）。
  @protected
  RenderMode previousMode(T oldWidget);

  /// 初始 source（默认从 coordinator 拿当前块 source）。
  String _initialSource() {
    return coordinator.sourceOf(blockId);
  }

  /// Block 点击处理：进入 editing 模式（子类可复用）。
  ///
  /// 防抖：若当前块已聚焦，跳过重复 setFocus（移动端手指微颤
  /// 会在 200-300ms 内产生多次 tap，避免无意义的状态通知）。
  void onBlockTap() {
    if (coordinator.focusedId == blockId) return;
    coordinator.setFocus(blockId);
  }

  /// 模式变化回调（子类可覆盖）。render ↔ editing 切换时回调。
  @protected
  void onModeChanged(RenderMode oldMode) {}

  /// 子类实现的 render 内容。由基类 `build()` 在 `RenderMode.rendered` 时调用。
  @protected
  Widget buildRenderContent(BuildContext context);

  // ============ edit 态 TextField 配置（子类可覆盖）============

  /// edit 态 [TextField] 的文本样式。默认 `null`。
  @protected
  TextStyle? get editFieldStyle => null;

  /// edit 态 [TextField] 的 [InputDecoration]。默认 [InputBorder.none]（去边框，
  /// 见 ADR-0020 D4：BlockRenderer 不绘制 box border，聚焦指示由 caret 提供）+ 水平12/垂直8 padding。
  @protected
  InputDecoration get editFieldDecoration => const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      );

  /// edit 态 [TextField] 的 maxLines。默认 `null`（多行）；标题块可覆盖为 `1`。
  @protected
  int? get editFieldMaxLines => null;

  /// 默认 [TextInputAction.newline]：软键盘回车插入 `\n`，由 [_enterFormatter]
  /// 拦截并派发 [EnterPressedIntent]（走 Intent Layer，而非不触发的 `onSubmitted`）。
  @protected
  TextInputAction get editFieldInputAction => TextInputAction.newline;

  /// 构造 edit 态 TextField。[_enterFormatter] 捕获软键盘 `\n` 派发
  /// [EnterPressedIntent]；[onSubmitted] 仅部分平台兜底。
  /// [onChanged] → [_onTextChanged]（Phase 3.3 PR #3 自动配对 / 续列表）。
  @protected
  Widget buildEditField({
    required TextStyle? style,
    required InputDecoration decoration,
    required int? maxLines,
    required TextInputAction inputAction,
    required List<TextInputFormatter> inputFormatters,
  }) {
    return TextField(
      controller: textController,
      focusNode: focusNode,
      style: style,
      maxLines: maxLines,
      textInputAction: inputAction,
      decoration: decoration,
      inputFormatters: inputFormatters,
      onChanged: _onTextChanged,
      onSubmitted: (_) => _onEnterSubmitted(),
    );
  }

  // ============ 回车分块（Phase A：经 Intent Layer）============

  /// 软键盘回车拦截（[EnterIntentFormatter] 捕获插入的 `\n`）→ 派发 [EnterPressedIntent]。
  void _onEnterIntercepted(int offset) {
    if (!isFocused) return;
    coordinator.intents.dispatch(EnterPressedIntent(
      blockId,
      TextSelection.collapsed(offset: offset),
    ));
  }

  // 兜底：真机（Xiaomi/MIUI）onSubmitted 为死代码（P0 已验证）；仅桌面/旧 IME 走此路径，resolver 同 offset 幂等不会双块（后续桌面 E2E 确认后可移除）。
  void _onEnterSubmitted() {
    if (!isFocused) return;
    final offset = textController.value.selection.baseOffset;
    if (offset < 0) return;
    coordinator.intents.dispatch(EnterPressedIntent(
      blockId,
      TextSelection.collapsed(offset: offset),
    ));
  }

  /// 记录用户输入交互事件（Phase 3.7.3）。
  ///
  /// **P1 信噪比修复（2026-08-06）**：改用 [UserInput.fromText] 工厂，
  /// 仅记录脱敏元信息（length / hasNewline / isAscii），不传原始文本。
  void _recordUserInput(String text) {
    coordinator.recordInteraction(
        obs.UserInput.fromText(text, DateTime.now()));
  }

  /// 输入变化回调：自动配对 + 自动续列表 + 立即 commit 统一入口。
  ///
  /// **v1.1 Hard Rule（§2.1.1）**：必须基于 [TextEditingController.value]
  /// （含 composing）而非 String 判断。composing region 非 collapsed 时
  /// 禁止自动行为（避免 IME 组合输入态触发配对 / 续行导致状态错乱）。
  ///
  /// **P0 修复（CORE-006/CORE-007）**：非 IME 输入立即 commit 到 domain
  /// （产生 Transaction 入 undo 栈），不再等待失焦。IME 组合态仍走 live 层。
  /// 这使 Undo 能撤销当前块的输入（而非其他块），且 canUndo 实时为 true。
  ///
  /// **职责边界**（§2.6）：
  /// - BaseBlockState 只负责"守门"（isFocused / composing / isCodeBlock）
  ///   + 持有 [_previousTextValue]（oldValue 来源）
  /// - 规则检测 + Command 派发委托 [_inputHandler]（不直接实现规则）
  /// - InputHandler 未处理时，BaseBlockState 直接 commit 原始输入
  void _onTextChanged(String text) {
    if (!isFocused) return; // 仅聚焦块处理

    // §2.1.1 Hard Rule：composing region 检查
    final value = textController.value;
    if (value.composing != TextRange.empty) return; // IME 组合输入态,跳过

    // ADR-0012：Live Editing State 实时上报（IME 组合态已在上方守卫跳过；
    // 此处更新 live 用于 wordCount / isDirty 实时刷新）
    coordinator.updateLiveSource(blockId, text);

    // Phase 3.7.3：记录用户输入交互事件
    _recordUserInput(text);

    // 块首退格合并（§4.1）：composing 守卫已在方法顶部；判定抽离到
    // [detectBackspaceMerge]（block_enter_intent_formatter.dart）。
    if (detectBackspaceMerge(_previousTextValue, value)) {
      coordinator.intents.dispatch(DeleteIntent(
        blockId,
        true,
        const TextSelection.collapsed(offset: 0),
      ));
      _previousTextValue = value;
      return; // flushLiveSource 在 IntentDispatcher 中对齐 live→domain
    }

    final oldValue = _previousTextValue ?? value;
    _previousTextValue = value;

    // §2.5 CodeBlock 例外：不应用自动配对 / 自动续列表,直接 commit
    if (coordinator.isFocusedOnCodeBlock) {
      _commitSource();
      return;
    }

    // §2.6 委托 InputHandler（传入 oldValue 供 AutoPairRules.detect 使用）
    // P0 修复：InputHandler 返回是否已派发 Command。未派发时 BaseBlockState
    // 直接 commit 原始输入，确保每次按键产生 Transaction 入 undo 栈。
    final handled = _inputHandler.handle(
      newValue: value,
      oldValue: oldValue,
      blockId: blockId,
      coordinator: coordinator,
    );
    if (!handled) {
      _commitSource();
    }
  }
}
