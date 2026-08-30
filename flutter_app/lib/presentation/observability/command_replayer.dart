/// CommandReplayer：基于 Command 事件流的确定性回放。
///
/// 从 Command 事件流重新执行用户操作，确定性复现问题现场。
/// 每步验证 AST 状态是否符合预期（通过 fingerprint 对比）。
///
/// **架构说明**：此类依赖 [CommandHandler] 与 [EditorCommand]（presentation 层），
/// 因此位于 `presentation/observability/` 而非 `core/observability/`。
/// 纯数据类 [ReplayCommandEvent] / [ReplayResult] 已下沉到
/// `core/observability/models.dart`，避免 core 反向依赖 presentation。
///
/// **ADR-0024 Extract**：核心重放循环逻辑已 Extract 到
/// `core/replay/replay_engine.dart`（[ReplayEngine]），本类实现
/// [ReplayCommandExecutor] 接口，负责 presentation 特定的
/// "反序列化 + 执行 + fingerprint 计算"，委托 [ReplayEngine] 驱动循环。
///
/// 落地 ADR-0021 §2.5（Layer 5：Command Replay System）+ §3.7.4 + ADR-0024 §2.3。
library;

import 'package:flutter/widgets.dart';

import '../../core/editing/block_types.dart';
import '../../core/observability/canonical_fingerprint.dart';
import '../../core/observability/models.dart' hide CommandOrigin;
import '../../core/replay/replay_engine.dart';
import '../../data/models/document.dart';
import '../commands/command_handler.dart';
import '../commands/commands.dart';

/// Command Replayer：基于 Command 事件流的确定性回放。
///
/// 加载 [ReplayCommandEvent] 列表，逐条驱动 [CommandHandler]，
/// 每步验证 AST 状态是否符合预期（通过 fingerprint 对比）。
///
/// **确定性保证**：
/// 1. [handler] 必须从固定 seed document 初始化（相同 BlockId 分配）
/// 2. 非确定性操作（DateTime.now()、随机数等）在 replay 中不启用
/// 3. BlockId 由 seed document 中的固定 ID 决定
///
/// **使用示例**：
/// ```dart
/// final editor = DocumentEditor(blocks: seedBlocks);
/// final handler = CommandHandler(editor: editor, history: EditorHistory());
/// final events = ReplayCommandEvent.loadFromJson(jsonString);
/// final replayer = CommandReplayer(handler: handler, events: events);
/// final results = replayer.replay();
/// ```
class CommandReplayer implements ReplayCommandExecutor {
  final CommandHandler handler;
  final List<ReplayCommandEvent> events;
  late final ReplayEngine _engine;

  CommandReplayer({
    required this.handler,
    required this.events,
  }) {
    _engine = ReplayEngine(executor: this, events: events);
  }

  /// 当前回放位置。
  int get index => _engine.index;

  /// 已完成的回放结果列表。
  List<ReplayResult> get results => _engine.results;

  /// 是否所有已回放命令均成功且 hash 匹配。
  bool get allSucceeded => _engine.allSucceeded;

  /// 失败的条数。
  int get failureCount => _engine.failureCount;

  /// 逐条重放所有 Command（委托 [ReplayEngine]）。
  List<ReplayResult> replay() => _engine.replay();

  /// 从指定位置开始重放（委托 [ReplayEngine]）。
  List<ReplayResult> replayFrom(int startIndex) => _engine.replayFrom(startIndex);

  /// [ReplayCommandExecutor] 实现：执行单条 replay 事件。
  ///
  /// 步骤 1：反序列化 [ReplayCommandEvent] → [EditorCommand]
  /// 步骤 2：执行 [CommandHandler.handle]
  /// 步骤 3：计算当前 Document fingerprint
  @override
  ReplayStepResult executeOne(ReplayCommandEvent event) {
    // 步骤 1：反序列化 Command
    EditorCommand? command;
    try {
      command = _deserializeCommand(event);
    } catch (e) {
      return ReplayStepResult(
        success: false,
        error: 'Deserialization failed: $e',
      );
    }

    // 步骤 2：执行 Command
    bool success;
    try {
      success = handler.handle(command);
    } catch (e) {
      return ReplayStepResult(
        success: false,
        error: 'Execution error: $e',
      );
    }

    // 步骤 3：计算 fingerprint
    final actualHash = _computeFingerprint();

    return ReplayStepResult(
      success: success,
      actualHash: actualHash,
    );
  }

  /// 计算当前 Document fingerprint。
  String? _computeFingerprint() {
    try {
      final blocks = handler.editor.allIds
          .map((id) => MapEntry<String, DocumentElement?>(
              id.value, handler.editor.getBlock(id)))
          .where((e) => e.value != null)
          .map((e) => MapEntry(e.key, e.value!))
          .toList();
      return canonicalFingerprint(blocks);
    } catch (_) {
      return null;
    }
  }

  // ============ 反序列化 ============

  /// 从 [ReplayCommandEvent] 反序列化为 [EditorCommand]。
  EditorCommand _deserializeCommand(ReplayCommandEvent event) {
    final origin = _parseOrigin(event.origin);
    final p = event.params;

    return switch (event.commandName) {
      'SplitBlockCommand' => SplitBlockCommand(
        blockId: _parseBlockId(p['blockId']),
        offset: p['offset'] as int,
        origin: origin,
      ),
      'MergeWithPreviousCommand' => MergeWithPreviousCommand(
        blockId: _parseBlockId(p['blockId']),
        origin: origin,
      ),
      'InsertBlockAfterCommand' => InsertBlockAfterCommand(
        blockId: _parseBlockId(p['blockId']),
        element: _parseElement(p['element']),
        origin: origin,
      ),
      'DeleteBlockCommand' => DeleteBlockCommand(
        blockId: _parseBlockId(p['blockId']),
        origin: origin,
      ),
      'MoveBlockUpCommand' => MoveBlockUpCommand(
        blockId: _parseBlockId(p['blockId']),
        origin: origin,
      ),
      'MoveBlockDownCommand' => MoveBlockDownCommand(
        blockId: _parseBlockId(p['blockId']),
        origin: origin,
      ),
      'MoveBlockCommand' => MoveBlockCommand(
        targetId: _parseBlockId(p['targetId']),
        refId: _parseBlockId(p['refId']),
        before: p['before'] as bool? ?? false,
        origin: origin,
      ),
      'UpdateBlockSourceCommand' => UpdateBlockSourceCommand(
        blockId: _parseBlockId(p['blockId']),
        newSource: p['newSource'] as String? ?? '',
        origin: origin,
      ),
      'TransformBlockCommand' => TransformBlockCommand(
        blockId: _parseBlockId(p['blockId']),
        origin: origin,
      ),
      'InsertTextCommand' => InsertTextCommand(
        blockId: _parseBlockId(p['blockId']),
        text: p['text'] as String? ?? '',
        cursorOffset: p['cursorOffset'] as int? ?? 0,
        selection: _parseSelection(p['selection']),
        origin: origin,
      ),
      'WrapSelectionCommand' => WrapSelectionCommand(
        blockId: _parseBlockId(p['blockId']),
        prefix: p['prefix'] as String? ?? '',
        suffix: p['suffix'] as String? ?? '',
        selection: _parseSelection(p['selection'])!,
        origin: origin,
      ),
      'InsertTemplateCommand' => InsertTemplateCommand(
        blockId: _parseBlockId(p['blockId']),
        template: p['template'] as String? ?? '',
        mode: _parseTemplateMode(p['mode']),
        selection: _parseSelection(p['selection']),
        cursorOffset: p['cursorOffset'] as int? ?? 0,
        origin: origin,
      ),
      'PairInsertCommand' => PairInsertCommand(
        blockId: _parseBlockId(p['blockId']),
        suffixChar: p['suffixChar'] as String? ?? '',
        insertOffset: p['insertOffset'] as int? ?? 0,
        mode: _parsePairInsertMode(p['mode']),
        cursorOffset: p['cursorOffset'] as int? ?? 0,
        origin: origin,
      ),
      'InsertNewLineWithPrefixCommand' => InsertNewLineWithPrefixCommand(
        blockId: _parseBlockId(p['blockId']),
        prefix: p['prefix'] as String? ?? '',
        isExit: p['isExit'] as bool? ?? false,
        origin: origin,
      ),
      _ => throw ArgumentError('Unknown command: ${event.commandName}'),
    };
  }

  // ============ 序列化（EditorCommand → ReplayCommandEvent） ============

  /// 将 [EditorCommand] 序列化为 [ReplayCommandEvent]。
  ///
  /// 用于在 CommandHandler 执行后，将 Command 记录为可重放的事件。
  static ReplayCommandEvent serialize(EditorCommand command) {
    final params = _serializeParams(command);
    return ReplayCommandEvent(
      commandName: command.runtimeType.toString(),
      params: params,
      origin: _serializeCommandOrigin(command.origin),
    );
  }

  /// 提取 Command 参数为可序列化 Map。
  static Map<String, Object?> _serializeParams(EditorCommand command) {
    return switch (command) {
      SplitBlockCommand(:final blockId, :final offset) => {
        'blockId': _serializeBlockId(blockId),
        'offset': offset,
      },
      MergeWithPreviousCommand(:final blockId) => {
        'blockId': _serializeBlockId(blockId),
      },
      InsertBlockAfterCommand(:final blockId, :final element) => {
        'blockId': _serializeBlockId(blockId),
        'element': elementToJson(element),
      },
      DeleteBlockCommand(:final blockId) => {
        'blockId': _serializeBlockId(blockId),
      },
      MoveBlockUpCommand(:final blockId) => {
        'blockId': _serializeBlockId(blockId),
      },
      MoveBlockDownCommand(:final blockId) => {
        'blockId': _serializeBlockId(blockId),
      },
      MoveBlockCommand(:final targetId, :final refId, :final before) => {
        'targetId': _serializeBlockId(targetId),
        'refId': _serializeBlockId(refId),
        'before': before,
      },
      UpdateBlockSourceCommand(:final blockId, :final newSource) => {
        'blockId': _serializeBlockId(blockId),
        'newSource': newSource,
      },
      TransformBlockCommand(:final blockId) => {
        'blockId': _serializeBlockId(blockId),
      },
      InsertTextCommand(
        :final blockId,
        :final text,
        :final cursorOffset,
        :final selection,
      ) => {
        'blockId': _serializeBlockId(blockId),
        'text': text,
        'cursorOffset': cursorOffset,
        if (selection != null) 'selection': _serializeSelection(selection),
      },
      WrapSelectionCommand(
        :final blockId,
        :final prefix,
        :final suffix,
        :final selection,
      ) => {
        'blockId': _serializeBlockId(blockId),
        'prefix': prefix,
        'suffix': suffix,
        'selection': _serializeSelection(selection),
      },
      InsertTemplateCommand(
        :final blockId,
        :final template,
        :final mode,
        :final selection,
        :final cursorOffset,
      ) => {
        'blockId': _serializeBlockId(blockId),
        'template': template,
        'mode': mode.name,
        if (selection != null) 'selection': _serializeSelection(selection),
        'cursorOffset': cursorOffset,
      },
      PairInsertCommand(
        :final blockId,
        :final suffixChar,
        :final insertOffset,
        :final mode,
        :final cursorOffset,
      ) => {
        'blockId': _serializeBlockId(blockId),
        'suffixChar': suffixChar,
        'insertOffset': insertOffset,
        'mode': mode.name,
        'cursorOffset': cursorOffset,
      },
      InsertNewLineWithPrefixCommand(
        :final blockId,
        :final prefix,
        :final isExit,
      ) => {
        'blockId': _serializeBlockId(blockId),
        'prefix': prefix,
        'isExit': isExit,
      },
    };
  }

  // ============ 类型序列化/反序列化辅助 ============

  /// BlockId 序列化：直接存 value 字符串。
  static String _serializeBlockId(BlockId id) => id.value;

  /// BlockId 反序列化：支持字符串或 {"value": "..."} 格式。
  static BlockId _parseBlockId(Object? value) {
    if (value is String) return BlockId(value);
    if (value is Map) {
      return BlockId((value as Map<String, Object?>)['value'] as String);
    }
    throw ArgumentError('Invalid BlockId: $value');
  }

  /// CommandOrigin 序列化：存 enum name。
  static String _serializeCommandOrigin(CommandOrigin origin) => origin.name;

  /// CommandOrigin 反序列化。
  static CommandOrigin _parseOrigin(String name) {
    return CommandOrigin.values.firstWhere(
      (o) => o.name == name,
      orElse: () => CommandOrigin.keyboard,
    );
  }

  /// TextSelection 序列化。
  static Map<String, Object?> _serializeSelection(TextSelection selection) {
    return {
      'baseOffset': selection.baseOffset,
      'extentOffset': selection.extentOffset,
      'affinity': selection.affinity.name,
      'isDirectional': selection.isDirectional,
    };
  }

  /// TextSelection 反序列化。
  static TextSelection? _parseSelection(Object? value) {
    if (value == null) return null;
    if (value is! Map) return null;
    final m = value as Map<String, Object?>;
    return TextSelection(
      baseOffset: m['baseOffset'] as int? ?? 0,
      extentOffset: m['extentOffset'] as int? ?? 0,
      affinity: _parseAffinity(m['affinity']),
      isDirectional: m['isDirectional'] as bool? ?? false,
    );
  }

  static TextAffinity _parseAffinity(Object? value) {
    if (value is! String) return TextAffinity.downstream;
    return TextAffinity.values.firstWhere(
      (a) => a.name == value,
      orElse: () => TextAffinity.downstream,
    );
  }

  static TemplateInsertMode _parseTemplateMode(Object? value) {
    if (value is! String) return TemplateInsertMode.insert;
    return TemplateInsertMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => TemplateInsertMode.insert,
    );
  }

  static PairInsertMode _parsePairInsertMode(Object? value) {
    if (value is! String) return PairInsertMode.appendAfterCursor;
    return PairInsertMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => PairInsertMode.appendAfterCursor,
    );
  }

  // ============ DocumentElement 反序列化 ============

  /// 从 JSON Map 解析 [DocumentElement]。
  static DocumentElement _parseElement(Object? value) {
    if (value is! Map) {
      return ParagraphElement(children: []);
    }
    final m = value as Map<String, Object?>;
    final type = m['type'] as String? ?? 'paragraph';
    return switch (type) {
      'paragraph' => ParagraphElement(
        children: _parseInlines(m['children']),
      ),
      'heading' => HeadingElement(
        level: m['level'] as int? ?? 1,
        text: m['text'] as String? ?? '',
      ),
      'list' => ListElement(
        ordered: m['ordered'] as bool? ?? false,
        indent: m['indent'] as int? ?? 0,
        children: _parseInlines(m['children']),
        nested: (m['nested'] as List?)
                ?.map((e) => _parseListElement(e as Map<String, dynamic>))
                .toList() ??
            const [],
      ),
      'code' => CodeElement(
        code: m['code'] as String? ?? '',
        language: m['language'] as String?,
      ),
      'table' => TableElement(
        headers: ((m['headers'] as List?) ?? [])
            .map((h) => _parseInlines(h as List))
            .toList(),
        rows: ((m['rows'] as List?) ?? [])
            .map(
              (r) => (r as List)
                  .map((c) => _parseInlines(c as List))
                  .toList(),
            )
            .toList(),
      ),
      'blockquote' => BlockquoteElement(
        children: _parseInlines(m['children'] as List? ?? []),
      ),
      'mermaid' => MermaidElement(
        code: m['code'] as String? ?? '',
      ),
      'empty_line' => EmptyLineElement(),
      'task_list_item' => TaskListItemElement(
        checked: m['checked'] as bool? ?? false,
        indent: m['indent'] as int? ?? 0,
        children: _parseInlines(m['children']),
      ),
      'horizontal_rule' => HorizontalRuleElement(),
      _ => ParagraphElement(children: []),
    };
  }

  static List<InlineElement> _parseInlines(Object? value) {
    if (value is! List) return [];
    return value.map((e) => _parseInline(e)).toList();
  }

  /// ADR-0029：解析嵌套 ListElement（serialize 时 ListElement.toJson 含 nested）。
  static ListElement _parseListElement(Map<String, Object?> m) {
    return ListElement(
      ordered: m['ordered'] as bool? ?? false,
      indent: m['indent'] as int? ?? 0,
      children: _parseInlines(m['children']),
      nested: (m['nested'] as List?)
              ?.map((e) => _parseListElement(e as Map<String, Object?>))
              .toList() ??
          const [],
    );
  }

  static InlineElement _parseInline(Object? value) {
    if (value is! Map) return TextElement('');
    final m = value as Map<String, Object?>;
    final type = m['type'] as String? ?? 'text';
    return switch (type) {
      'text' => TextElement(m['text'] as String? ?? ''),
      'formula' => FormulaElement(
        latex: m['latex'] as String? ?? '',
        displayMode: m['displayMode'] as bool? ?? false,
      ),
      'bold' => BoldElement(children: _parseInlines(m['children'])),
      'italic' => ItalicElement(children: _parseInlines(m['children'])),
      'strikethrough' =>
        StrikethroughElement(children: _parseInlines(m['children'])),
      'inline_code' => InlineCodeElement(m['code'] as String? ?? ''),
      'link' => LinkElement(
        text: m['text'] as String? ?? '',
        url: m['url'] as String? ?? '',
      ),
      'image' => ImageElement(
        alt: m['alt'] as String? ?? '',
        url: m['url'] as String? ?? '',
      ),
      _ => TextElement(''),
    };
  }
}