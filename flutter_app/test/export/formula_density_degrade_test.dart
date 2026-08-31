/// P0-D（ADR-0032）Export Assembly Finite Guarantee 回归单测。
///
/// 验证预防性公式密度降级机制（forceTextFormula + kAssemblyFormulaDensityLimit）
/// 在分片渲染时正确触发并保证导出完成——防止多公式 SVG 密度触发的真机卡死
/// （Case E：30 块 + 12 公式 addPage 永久阻塞）再次出现。
///
/// 注意：单测环境公式不卡（纯 Dart 118 真实 SVG 30s 内完成），本测试是
/// 回归保护（降级重建逻辑 slice = rebuilt + forceTextFormula 链不破坏导出），
/// 降级有效性由真机 Case E 验证覆盖（详见 ADR-0032 §真机验证）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/domain/services/exporters/pdf_exporter.dart';
import 'package:tafcm/domain/services/export_service.dart';

void main() {
  group('P0-D Export Assembly Finite（ADR-0032）', () {
    test('高密度公式片（≥8 公式）降级重建后导出正常完成', () async {
      // Case E 真机复现：30 块 + 12 公式 SVG → addPage 永久卡死（60s+）。
      // P0-D 预防性降级：片内公式数 ≥ kAssemblyFormulaDensityLimit(8) → 该片
      // 公式降级为文本重建（forceTextFormula）。本测试是回归保护——降级重建逻辑
      // （slice = rebuilt + forceTextFormula 链）不破坏导出流程，导出正常完成。
      final formulas =
          List.generate(10, (i) => r'$x_{' '$i' r'}^2$').join(' ');
      final md = '高密度公式段落 $formulas。';
      final bytes = await MarkdownExporter.exportToPdf(md);
      expect(bytes.isNotEmpty, true,
          reason: '高密度公式片降级重建后导出应正常完成（回归保护）');
      // 密度阈值常量存在且可读（分片降级判断的 API 契约）。
      expect(PdfExporter.kAssemblyFormulaDensityLimit, 8);
    });

    test('阈值常量契约：kAssemblyFormulaDensityLimit = 8（安全余量）', () {
      // B-3 差分：30 块 + 12 公式卡 / 30 块 + 1 公式 116ms 正常。
      // 阈值 8 = 12 与 1 之间的安全余量：≥ 8 时降级（防多公式卡死），
      // < 8 时保留 SVG（保证质量）。本断言守护契约不变。
      expect(PdfExporter.kAssemblyFormulaDensityLimit, 8);
    });
  });
}
