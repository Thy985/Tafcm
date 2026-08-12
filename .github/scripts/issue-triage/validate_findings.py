#!/usr/bin/env python3
"""validate_findings.py — D7 契约 Gate。

对 Claude 输出的 findings.json 做严格结构校验。未通过则以退出码 1 结束，
调用方（create job）必须不产生任何 GitHub 副作用（create_issues.sh 不应被继续执行）。

用法:
    python validate_findings.py <findings.json> [<schema.json>]

依赖: 仅标准库。schema.json 用于提示/审计，实际判定规则固化在下方常量，
避免运行环境缺少 jsonschema 依赖导致校验失效。
"""

import json
import re
import sys

CATEGORIES = frozenset({
    "bug", "security", "performance", "tech-debt", "refactor",
    "feature-request", "documentation",
})
SEVERITIES = frozenset({"critical", "high", "medium", "low"})
SOURCE_TYPES = frozenset({
    "pull_request_review", "pull_request_review_comment", "branch_scan",
})
TRUST_LEVELS = frozenset({"maintainer", "member", "contributor", "fork"})

_REQUIRED_FINDING = frozenset({
    "id", "title", "body", "category", "severity", "priority",
    "confidence", "component", "root_cause", "labels", "mentions", "source_ref",
})
_REQUIRED_SOURCE = frozenset({"type", "pr", "branch", "base", "trust_level", "fetched_at"})
_KEBAB = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def _fail(msg):
    print(f"VALIDATE FAIL: {msg}")
    return False


def validate_source(source):
    ok = True
    if not isinstance(source, dict):
        return _fail("source 必须是对象")
    for key in _REQUIRED_SOURCE:
        if key not in source:
            ok = _fail(f"source 缺少必填字段: {key}")
    if "type" in source and source["type"] not in SOURCE_TYPES:
        ok = _fail(f"source.type 非法: {source['type']}")
    if "trust_level" in source and source["trust_level"] not in TRUST_LEVELS:
        ok = _fail(f"source.trust_level 非法: {source['trust_level']}")
    return ok


def validate_finding(f):
    """逐条校验 finding；返回 (ok, errors)。"""
    errors = []
    if not isinstance(f, dict):
        errors.append("finding 必须是对象")
        return False, errors
    for key in _REQUIRED_FINDING:
        if key not in f:
            errors.append(f"缺少必填字段: {key}")
    if "category" in f and f["category"] not in CATEGORIES:
        errors.append(f"category 非法: {f['category']}")
    if "severity" in f and f["severity"] not in SEVERITIES:
        errors.append(f"severity 非法: {f['severity']}")
    if "priority" in f and f["priority"] not in SEVERITIES:
        errors.append(f"priority 非法: {f['priority']}")
    if "confidence" in f:
        c = f["confidence"]
        if not isinstance(c, (int, float)) or isinstance(c, bool):
            errors.append("confidence 必须是数值")
        elif not (0 <= c <= 1):
            errors.append(f"confidence 超出 [0,1]: {c}")
    for field in ("component", "root_cause"):
        if field in f:
            v = f[field]
            if not isinstance(v, str) or not _KEBAB.match(v):
                errors.append(f"{field} 必须是非空 kebab-case 字符串: {v!r}")
    if "labels" in f and not isinstance(f["labels"], list):
        errors.append("labels 必须是数组")
    if "mentions" in f and not isinstance(f["mentions"], list):
        errors.append("mentions 必须是数组")
    if "source_ref" in f and not isinstance(f["source_ref"], str):
        errors.append("source_ref 必须是字符串")
    return (len(errors) == 0, errors)


def validate_doc(doc):
    ok = True
    if not isinstance(doc, dict):
        return _fail("findings.json 根节点必须是对象")
    if "schema_version" not in doc:
        ok = _fail("缺少 schema_version")
    if "summary" not in doc:
        ok = _fail("缺少 summary")
    if "source" not in doc:
        ok = _fail("缺少 source")
    else:
        ok = validate_source(doc["source"]) and ok
    if "findings" not in doc:
        ok = _fail("缺少 findings")
    elif not isinstance(doc["findings"], list):
        ok = _fail("findings 必须是数组")
    else:
        issues = doc["findings"]
        for i, f in enumerate(issues):
            valid, errs = validate_finding(f)
            if not valid:
                ok = False
                for e in errs:
                    print(f"VALIDATE FAIL: findings[{i}]: {e}")
        ids = [f.get("id") for f in issues if isinstance(f, dict)]
        if len(ids) != len(set(ids)):
            ok = _fail("findings.id 存在重复")
    return ok


def main(argv):
    if len(argv) < 2:
        print("usage: validate_findings.py <findings.json> [<schema.json>]", file=sys.stderr)
        return 2
    findings_path = argv[1]
    try:
        with open(findings_path, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
    except json.JSONDecodeError as e:
        print(f"VALIDATE FAIL: findings.json 不是合法 JSON: {e}")
        return 1
    except OSError as e:
        print(f"VALIDATE FAIL: 无法读取 {findings_path}: {e}")
        return 1

    if len(argv) >= 3:
        # 仅提示 schema 位置，不依赖外部解析库
        print(f"(schema 参考: {argv[2]})")

    if validate_doc(doc):
        count = len(doc.get("findings", []))
        print(f"VALIDATE OK: findings.json 合法，共 {count} 条 finding")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
