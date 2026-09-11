# Spec Test Data（U1 CommonMark 一致性套件数据源）

> 生成与消费方式见 [TEST-SYSTEM-UPGRADE-PLAN.md](../../../../docs/engineering/TEST-SYSTEM-UPGRADE-PLAN.md) §3.1。

| 文件 | 来源 | 许可 |
|------|------|------|
| `spec.txt` | [commonmark-spec 0.31.2](https://spec.commonmark.org/0.31.2/) 官方发布文件 | **CC-BY-SA 4.0**（版权 © John MacFarlane，含 652 个 `markdown ↔ html` 一致性用例） |
| `examples.json` | 由 `tool/gen_spec_examples.dart` 从 spec.txt 抽取生成（勿手改，再生成命令：`dart run tool/gen_spec_examples.dart`） | 衍生自 spec.txt，同 **CC-BY-SA 4.0** |

## 引用声明（许可要求）

本目录测试数据源自 CommonMark spec：

> commonmark-spec by John MacFarlane, licensed under
> [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
> Source: https://github.com/commonmark/commonmark-spec (tag 0.31.2)

修改分发（含本项目仓库内的衍生 JSON）须保持相同许可并注明出处。

## 数据格式

```json
{
  "section": "Setext headings",
  "number": 50,
  "markdown": "Foo\n===\n",
  "html": "<h1>Foo</h1>\n",
  "disabled": false
}
```

- `disabled: true` = spec 官方标记跳过的用例（0.31.2 中为 0 条）
- 守门测试按 `section` 聚合通过率，基线 ratchet 见 `commonmark_conformance_test.dart`
