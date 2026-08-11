/// ADI Validation Adapter：replay + invariant 验证闭环。
///
/// Agent 修复代码后调用 `validate(sessionId)`，自动执行：
/// 1. Replay 原 session（验证错误不再复现）
/// 2. Invariant Check（验证全部不变量通过）
/// 3. 返回 AdiValidationResultView（before/after 分类）
///
/// v0.2 只做 Replay + Invariant，不含 flutter test 子集（留 ADR-0026）。
///
/// 落地 ADR-0024 §2.4（Validation Adapter）。
library;

import 'adi_replay_adapter.dart';
import 'adi_view.dart';

import 'observability_service.dart';

/// 验证适配器抽象接口。
abstract class AdiValidationAdapter {
  /// 修复后验证（对应 CLI: adi validate --after-fix）。
  ///
  /// [sessionId]：要验证的 session。
  /// [before]：修复前的问题分类（Agent 提供，用于对比）。
  AdiValidationResultView validate({
    required String sessionId,
    AdiValidationBefore before = AdiValidationBefore.unknown,
  });
}

/// 验证适配器实现。
class AdiValidationAdapterImpl implements AdiValidationAdapter {
  final AdiReplayAdapter _replayAdapter;
  final ObservabilityService _service;

  AdiValidationAdapterImpl(this._replayAdapter, this._service);

  @override
  AdiValidationResultView validate({
    required String sessionId,
    AdiValidationBefore before = AdiValidationBefore.unknown,
  }) {
    final replayResult = _replayAdapter.replay(sessionId);
    final invariantReport = _service.lastInvariantReport;

    final crossSessionWarning =
        invariantReport != null && _service.sessionId != sessionId;

    final violated = invariantReport?.failedNames ?? [];
    final checked = invariantReport?.allNames ?? [];
    final invariants = AdiInvariantView(
      violated: violated,
      checked: checked,
    );

    final replayOk = replayResult.status != AdiReplayStatus.reproduced;
    final invariantOk = invariants.allPassed;

    final after = _classifyAfter(
      replayOk: replayOk,
      invariantOk: invariantOk,
      replayStatus: replayResult.status,
      crossSessionWarning: crossSessionWarning,
    );

    return AdiValidationResultView(
      before: before,
      after: after,
      replayResult: replayResult,
      invariants: invariants,
      crossSessionDataWarning: crossSessionWarning,
    );
  }

  AdiValidationAfter _classifyAfter({
    required bool replayOk,
    required bool invariantOk,
    required AdiReplayStatus replayStatus,
    required bool crossSessionWarning,
  }) {
    if (replayStatus == AdiReplayStatus.inconclusive) {
      return AdiValidationAfter.inconclusive;
    }
    if (crossSessionWarning) {
      return AdiValidationAfter.inconclusive;
    }
    if (replayOk && invariantOk) {
      return AdiValidationAfter.pass;
    }
    return AdiValidationAfter.stillFailing;
  }
}