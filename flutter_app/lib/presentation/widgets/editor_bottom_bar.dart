import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class EditorBottomBar extends StatelessWidget {
  final bool isPreview;
  final bool isExporting;
  final VoidCallback onTogglePreview;
  final VoidCallback onExport;

  const EditorBottomBar({
    super.key,
    required this.isPreview,
    required this.isExporting,
    required this.onTogglePreview,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        // TODO(UI): 底色应随主题（PR-F 即时颜色项），本 PR 只接阴影令牌。
        color: Colors.white,
        // 底部栏向上投影：取主题对应档位后翻转 Y 轴（P0-1）。
        boxShadow: AppShadows.flipY(AppShadows.of(context).md),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onTogglePreview,
                icon: Icon(isPreview ? Icons.edit : Icons.visibility),
                label: Text(isPreview ? '编辑' : '预览'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isExporting ? null : onExport,
                icon: isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.file_download),
                label: Text(isExporting ? '导出中...' : '导出'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
