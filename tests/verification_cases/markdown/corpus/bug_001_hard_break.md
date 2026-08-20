# BUG-001 Regression Trigger — multiline paragraph hard break

这是一段多行段落。

第一行硬换行后继续内容，round-trip 时若丢失 '\n' 则 AST 结构不一致（BUG-1）。

行内公式 $E=mc^2$ 与普通文本混合，验证 parse→serialize→parse 不动点。

- 列表项一
- 列表项二

```dart
final x = 1;
```

| 列A | 列B |
|-----|-----|
| 1   | 2   |

> 引用块内多行文本，同样依赖硬换行保留。
