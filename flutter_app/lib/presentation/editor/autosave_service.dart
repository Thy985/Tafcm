/// AutosaveService：独立自动保存服务（ADR-0013 Autosave Architecture）。
///
/// **职责**（ADR-0013 §职责边界）：
/// - 监听 [DirtyStateSource.dirtyChanges]（脏状态翻转）
/// - debounce（默认 dirty 后 1.5s，连续编辑只触发一次保存）
/// - 调用注入的 save 回调（与手动保存共用同一落盘路径，保持幂等）
/// - 保存成功后回调 [DirtyStateSource.markSaved] 重置脏标记 + 定时器
/// - 持久化失败时**指数退避重试**（避免以 debounce 间隔空转成风暴）
///
/// **不负责**（ADR-0013）：文档状态管理（属 Coordinator）/ Command 构造 /
/// UI 渲染（「已保存」轻提示由 chrome 订阅 [status] 后展示）。
///
/// **依赖方向（架构守门）**：本文件**只 import [dirty_state_source.dart]**，
/// 不 import `blocks/` / `chrome/`。save 逻辑通过回调注入，无全局静态单例。
library;

import 'dart:async';

import 'dirty_state_source.dart';

/// AutosaveService 运行态（供 chrome 订阅展示轻提示）。
enum AutosaveStatus {
  /// 空闲 / 无待保存改动。
  idle,

  /// 正在保存（debounce 已到期，save 回调执行中）。
  saving,

  /// 保存成功（可展示「已自动保存」轻提示）。
  saved,

  /// 保存失败（已捕获异常，不会崩溃，即将退避重试）。
  error,

  /// 失败后已排入重试，退避等待中。**UI 不应将其解读为「已保存」**——
  /// 与 [idle] 语义不同：[idle] 表示无待处理保存；[retrying] 表示失败且
  /// 即将自动重试（见 ADR-0013 验证计划「失败重试退避」）。
  retrying,
}

/// 可注入的定时器工厂（默认 [Timer.new]，测试可替换为受控时钟）。
typedef AutosaveTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

/// 独立自动保存服务（ADR-0013）。
///
/// 设计要点：
/// - **去 Coordinator 耦合**：仅依赖抽象 [DirtyStateSource] + 注入的 save 回调。
/// - **并发保存串行化**：`_inflight` future 保证同一时刻只有一个 save 在飞；
///   保存中又变脏时重新调度，绝不交错（禁止 A 覆盖 B 把旧内容回写，见 ADR-0013
///   验证计划「并发保存保护」）。
/// - **触发时刻快照**：save 回调应在其**起始同步**捕获文档快照（本服务在 timer
///   触发时立即调用 save，回调内同步读取即等于触发时刻快照），避免把进行中的实时
///   live 写盘造成回退。
/// - **保存中再变脏**：不误调 [DirtyStateSource.markSaved]（否则会丢掉保存中新产生的
///   编辑），改为重新调度，下一次 save 基于最新 source。
/// - **失败退避重试**：持久化异常被捕获，按 [maxRetryDelay] 封顶的指数退避重新保存，
///   避免磁盘满/权限拒绝/文件锁定等场景下以 debounce 间隔不断重试造成文件系统压力。
class AutosaveService {
  final DirtyStateSource _source;
  final Future<bool> Function() _save;
  final Duration _debounce;
  final Duration _maxRetryDelay;
  final AutosaveTimerFactory _timerFactory;

  Timer? _timer;
  Future<void>? _inflight;
  StreamSubscription<bool>? _sub;
  StreamController<AutosaveStatus>? _statusCtl;

  /// 失败重试退避间隔（指数增长，封顶 [_maxRetryDelay]）。
  /// [Duration.zero] 表示当前处于正常编辑窗口（非重试态）。
  Duration _retryDelay = Duration.zero;

  AutosaveService({
    required DirtyStateSource source,
    required Future<bool> Function() save,
    Duration debounce = const Duration(milliseconds: 1500),
    Duration maxRetryDelay = const Duration(seconds: 60),
    AutosaveTimerFactory timerFactory = Timer.new,
  })  : _source = source,
        _save = save,
        _debounce = debounce,
        _maxRetryDelay = maxRetryDelay,
        _timerFactory = timerFactory;

  /// 状态流（idle / saving / saved / error / retrying），chrome 订阅展示轻提示。
  ///
  /// 惰性创建 [StreamController]：stop() 关闭后可经再次 start() 复用，
  /// 解决「stop() 后不可重用」问题（ADR-0013 评审）。
  Stream<AutosaveStatus> get status {
    _statusCtl ??= StreamController<AutosaveStatus>.broadcast();
    return _statusCtl!.stream;
  }

  /// 启动：订阅脏状态流；若启动时已脏则立即调度一次。
  void start() {
    _statusCtl ??= StreamController<AutosaveStatus>.broadcast();
    _sub = _source.dirtyChanges.listen(_onDirtyChange);
    if (_source.isDirty) _schedule(); // 用户编辑窗口：退避归零
  }

  /// 停止：取消订阅 + 定时器 + 关闭状态流。应在 owner dispose 时调用。
  /// 之后可再次调用 [start] 复用本实例。
  void stop() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _statusCtl?.close();
    _statusCtl = null;
  }

  void _onDirtyChange(bool dirty) {
    // 只在「变脏」时调度；变干净由本服务在保存成功后主动 markSaved，不在此处理。
    // 用户编辑窗口重置退避（不论之前是否处于重试态）。
    if (dirty) _schedule();
  }

  /// 正常 debounce 调度（用户编辑驱动）：退避归零，按 [_debounce] 计时。
  void _schedule() {
    _retryDelay = Duration.zero;
    _timer?.cancel();
    _timer = _timerFactory(_debounce, _fire);
  }

  /// 失败重试调度：指数退避（首次 = [_debounce]，之后 ×2，封顶 [_maxRetryDelay]）。
  void _scheduleRetry() {
    _retryDelay =
        _retryDelay == Duration.zero ? _debounce : _retryDelay * 2;
    if (_retryDelay > _maxRetryDelay) _retryDelay = _maxRetryDelay;
    _timer?.cancel();
    _timer = _timerFactory(_retryDelay, _fire);
  }

  Future<void> _fire() async {
    // 已有保存在飞：直接返回，进行中的保存会在完成后自行重评估（见 _saveOnce）。
    if (_inflight != null) return;
    final completer = Completer<void>();
    _inflight = completer.future;
    try {
      await _saveOnce();
    } finally {
      _inflight = null;
      completer.complete();
    }
  }

  Future<void> _saveOnce() async {
    _emit(AutosaveStatus.saving);
    final bool saved;
    try {
      // save 回调在起始同步捕获文档快照（触发时刻），避免写盘进行中的实时 live；
      // 写盘完成后若 source 无新改动，由 save 回调自行调用 markSaved（重置脏标记）。
      // 把 markSaved 交给回调而非本服务，是因为「写盘期间是否有新编辑」只有持有快照的
      // 回调能判断（ADR-0013 并发保护：禁止 A 的 markSaved 误清 B 进行中的编辑）。
      saved = await _save();
    } catch (e) {
      // 持久化失败（磁盘满 / 权限拒绝 / 文件锁定）：捕获异常不崩溃，
      // 进入退避重试（避免以 debounce 间隔空转成风暴）。
      _emit(AutosaveStatus.error);
      _emit(AutosaveStatus.retrying);
      _scheduleRetry();
      return;
    }
    if (!saved) {
      // 未真正落盘（如无可写路径）：保留 dirty，不 markSaved、不重试（避免空转）。
      _emit(AutosaveStatus.idle);
      return;
    }
    if (_source.isDirty) {
      // save 回调未 markSaved（写盘期间产生了新编辑）：不误清，重新 debounce。
      _emit(AutosaveStatus.idle);
      _schedule();
      return;
    }
    // 成功且 source 已无新改动：标记已保存并重置退避。
    _retryDelay = Duration.zero;
    _emit(AutosaveStatus.saved);
  }

  void _emit(AutosaveStatus s) {
    final ctl = _statusCtl;
    if (ctl != null && !ctl.isClosed) ctl.add(s);
  }
}
