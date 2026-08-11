/// ADI Context Generator：生成 Agent 可直接消费的 Markdown 上下文。
///
/// 升级现有 analyze.py 的输出，给 Agent Observation + Context + Hypothesis，
/// 不给确定答案。hypotheses 标 confidence: "hypothesis"。
///
/// 落地 ADR-0024 §2.5（Agent Context Generator）。
library;

import 'adi_query_adapter.dart';

import 'observability_service.dart';

/// 上下文生成器抽象接口。
abstract class AdiContextGenerator {
  String generateAgentContext();
}

/// 上下文生成器实现。
class AdiContextGeneratorImpl implements AdiContextGenerator {
  final AdiQueryAdapter _queryAdapter;
  final ObservabilityService _service;

  AdiContextGeneratorImpl(this._queryAdapter, this._service);

  @override
  String generateAgentContext() {
    final buf = StringBuffer();
    buf.writeln('# Current Software State');
    buf.writeln();

    _writeLastFailure(buf);
    _writeReproduction(buf);
    _writeEvidence(buf);
    _writeHypotheses(buf);
    _writeInvariantStatus(buf);
    _writeNextActions(buf);

    return buf.toString();
  }

  void _writeLastFailure(StringBuffer buf) {
    final error = _queryAdapter.latestError();
    buf.writeln('## Last failure');
    if (error == null) {
      buf.writeln('No errors recorded.');
    } else {
      buf.writeln('${error.errorType}: ${error.message}');
      buf.writeln('- quality: ${error.quality.name}');
      if (error.commandName != null) {
        buf.writeln('- command: ${error.commandName}');
      }
    }
    buf.writeln();
  }

  void _writeReproduction(StringBuffer buf) {
    final error = _queryAdapter.latestError();
    buf.writeln('## Reproduction');
    if (error == null) {
      buf.writeln('N/A (no failure to reproduce)');
    } else if (error.replayAvailable) {
      buf.writeln('Replay data available. Run: `adi replay ${error.sessionId ?? "unknown"}`');
    } else {
      buf.writeln('No replay data available for this session.');
    }
    buf.writeln();
  }

  void _writeEvidence(StringBuffer buf) {
    final error = _queryAdapter.latestError();
    buf.writeln('## Evidence');
    if (error == null) {
      buf.writeln('No evidence collected.');
    } else {
      buf.writeln('- trace_id: ${error.traceId}');
      if (error.sessionId != null) {
        buf.writeln('- session_id: ${error.sessionId}');
      }
      if (error.snapshotPath != null) {
        buf.writeln('- snapshot: ${error.snapshotPath}');
      }
    }
    buf.writeln();
  }

  void _writeHypotheses(StringBuffer buf) {
    final error = _queryAdapter.latestError();
    buf.writeln('## Suspected location (Hypothesis, not confirmed)');
    if (error == null || error.hypotheses.isEmpty) {
      buf.writeln('No hypotheses available.');
    } else {
      for (final h in error.hypotheses) {
        buf.writeln('- ${h.file}:${h.line} — ${h.reason}');
        buf.writeln('  (confidence: ${h.confidence}${h.verified ? ", verified" : ""})');
      }
    }
    buf.writeln();
  }

  void _writeInvariantStatus(StringBuffer buf) {
    final report = _service.lastInvariantReport;
    buf.writeln('## Invariant status');
    if (report == null) {
      buf.writeln('No invariant report available.');
    } else if (report.failedNames.isEmpty) {
      buf.writeln('All ${report.allNames.length} invariants satisfied.');
      buf.writeln('(rendering degradation or established behavior, not state corruption — ADR-0022)');
    } else {
      buf.writeln('VIOLATED: ${report.failedNames.join(", ")}');
      buf.writeln('(state corruption — real bug)');
    }
    buf.writeln();
  }

  void _writeNextActions(StringBuffer buf) {
    final error = _queryAdapter.latestError();
    buf.writeln('## Suggested next action');
    if (error != null) {
      if (error.sessionId != null) {
        buf.writeln('- Confirm: `adi replay ${error.sessionId}`');
      }
      buf.writeln('- Inspect: `adi trace show ${error.traceId}`');
    } else {
      buf.writeln('- No action needed (no failures recorded).');
    }
    buf.writeln();
  }
}