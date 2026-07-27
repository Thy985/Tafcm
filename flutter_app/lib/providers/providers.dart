import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/document.dart';
import 'file_repository_provider.dart';

// 注意：主题状态（darkModeProvider / themeModeProvider / sharedPreferencesProvider）
// 的权威定义已统一收敛到 `providers/editor_providers.dart`，本文件不再重复定义，
// 以修复 AGENTS.md §3.2「禁止在多个文件定义同名 Provider」的重复定义 bug
// （与 previewModeProvider 先例一致）。

// ============ Documents List ============

final documentsProvider = StateNotifierProvider<DocumentsNotifier, AsyncValue<List<Document>>>((ref) {
  final repo = ref.watch(fileRepositoryProvider);
  return DocumentsNotifier(repo);
});

class DocumentsNotifier extends StateNotifier<AsyncValue<List<Document>>> {
  final DocumentRepository _repo;

  DocumentsNotifier(this._repo) : super(const AsyncValue.loading()) {
    loadDocuments();
  }

  Future<void> loadDocuments() async {
    state = const AsyncValue.loading();
    try {
      final docs = await _repo.listDocuments();
      state = AsyncValue.data(docs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Document> createDocument(String title, String content) async {
    final path = await _repo.createDocument(title, content);
    final doc = await _repo.readDocument(path);
    state.whenData((docs) {
      state = AsyncValue.data([doc, ...docs]);
    });
    return doc;
  }

  Future<void> deleteDocument(String id) async {
    final path = await _repo.documentPathFor(id);
    await _repo.deleteDocument(path);
    state.whenData((docs) {
      state = AsyncValue.data(docs.where((d) => d.id != id).toList());
    });
  }
}

// ============ Current Document ============

final currentDocumentProvider = StateNotifierProvider<CurrentDocumentNotifier, Document?>((ref) {
  return CurrentDocumentNotifier();
});

class CurrentDocumentNotifier extends StateNotifier<Document?> {
  CurrentDocumentNotifier() : super(null);

  void setDocument(Document doc) {
    state = doc;
  }

  void updateContent(String content) {
    if (state != null) {
      state = state!.copyWith(content: content, updatedAt: DateTime.now());
    }
  }

  void updateTitle(String title) {
    if (state != null) {
      state = state!.copyWith(title: title, updatedAt: DateTime.now());
    }
  }

  void clear() {
    state = null;
  }
}

// ============ Editor Content + History ============
//
// **Phase 3.1-A PR #2 变更**：
// `previewModeProvider` 从本文件移除（原违反 AGENTS.md §3.2「禁止在多个文件定义同名
// Provider」）。唯一权威定义位于 `providers/editor_providers.dart`，仅供 legacy
// `EditorScreen` fallback 使用。新 `EditorPage` 路径不再使用 previewMode（WYSIWYG 范式）。

final isExportingProvider = StateProvider<bool>((ref) => false);
final searchQueryProvider = StateProvider<String>((ref) => '');

final editorContentProvider = StateNotifierProvider<EditorContentNotifier, String>((ref) {
  return EditorContentNotifier();
});

class EditorContentNotifier extends StateNotifier<String> {
  EditorContentNotifier() : super('');

  void setContent(String content) {
    state = content;
  }

  void clear() {
    state = '';
  }
}

// ============ Search ============

final filteredDocumentsProvider = Provider<List<Document>>((ref) {
  final docsAsync = ref.watch(documentsProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();

  return docsAsync.when(
    data: (docs) {
      if (query.isEmpty) return docs;
      return docs.where((d) =>
        d.title.toLowerCase().contains(query) ||
        d.content.toLowerCase().contains(query)
      ).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});