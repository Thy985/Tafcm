#!/usr/bin/env python3
"""JSON Schema 子集实例校验器（纯 stdlib）。

存在理由：治理红线要求"每个写步骤写前校验 + KB 硬顶"，而 CI runner 与本地都不保证
有 `jsonschema` 包，控制面也不该为一个校验能力引入第三方依赖。本模块实现
`.github/schemas/*.schema.json` 实际用到的关键字子集：

    $ref(draft-07 本地指针) / type(含 null 与类型联合) / enum / const /
    required / properties / additionalProperties(bool|schema) /
    items(schema) / minItems / maxItems / pattern / minimum / maximum

不支持的字段一律忽略（与 draft-07 语义一致）。返回错误路径列表，空列表 = 通过。
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

_TYPE_CHECKS = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "boolean": lambda v: isinstance(v, bool),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "null": lambda v: v is None,
}


def _resolve_ref(root: dict, ref: str) -> dict:
    if not ref.startswith("#/"):
        return {}
    node: Any = root
    for part in ref[2:].split("/"):
        if not isinstance(node, dict):
            return {}
        node = node.get(part.replace("~1", "/"), {})
    return node if isinstance(node, dict) else {}


def validate(instance: Any, schema: dict, root: dict | None = None,
             path: str = "$") -> list[str]:
    """校验 instance 是否符合 schema，返回人类可读的错误路径列表。"""
    if root is None:
        root = schema
    errors: list[str] = []

    if not isinstance(schema, dict):
        return errors

    if "$ref" in schema:
        schema = _resolve_ref(root, schema["$ref"])
        if not schema:
            return [f"{path}: 无法解析 $ref"]

    if "type" in schema:
        types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_TYPE_CHECKS.get(t, lambda _: True)(instance) for t in types):
            errors.append(f"{path}: 类型应为 {types}，实际 {type(instance).__name__}")
            return errors

    if "const" in schema and instance != schema["const"]:
        errors.append(f"{path}: 值应为 {schema['const']!r}")

    if "enum" in schema:
        allowed = set()
        for v in schema["enum"]:
            allowed.add(json.dumps(v, sort_keys=True))
        if json.dumps(instance, sort_keys=True) not in allowed:
            errors.append(f"{path}: 值 {instance!r} 不在枚举内 {schema['enum']}")

    if isinstance(instance, dict):
        props = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in instance:
                errors.append(f"{path}.{key}: required 字段缺失")
        additional = schema.get("additionalProperties", True)
        for key, value in instance.items():
            if key in props:
                errors += validate(value, props[key], root, f"{path}.{key}")
            elif additional is False:
                errors.append(f"{path}.{key}: 未声明的字段（additionalProperties=false）")
            elif isinstance(additional, dict):
                errors += validate(value, additional, root, f"{path}.{key}")

    if isinstance(instance, list):
        if "minItems" in schema and len(instance) < schema["minItems"]:
            errors.append(f"{path}: 数组长度 {len(instance)} < minItems {schema['minItems']}")
        if "maxItems" in schema and len(instance) > schema["maxItems"]:
            errors.append(f"{path}: 数组长度 {len(instance)} > maxItems {schema['maxItems']}")
        items = schema.get("items")
        if isinstance(items, dict):
            for i, element in enumerate(instance):
                errors += validate(element, items, root, f"{path}[{i}]")

    if isinstance(instance, str) and "pattern" in schema:
        if not re.search(schema["pattern"], instance):
            errors.append(f"{path}: 不匹配 pattern {schema['pattern']}")

    if isinstance(instance, (int, float)) and not isinstance(instance, bool):
        if "minimum" in schema and instance < schema["minimum"]:
            errors.append(f"{path}: {instance} < minimum {schema['minimum']}")
        if "maximum" in schema and instance > schema["maximum"]:
            errors.append(f"{path}: {instance} > maximum {schema['maximum']}")

    return errors


def load_schema(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


if __name__ == "__main__":  # 手工冒烟：python contract_minicheck.py <schema> <instance>
    import sys

    sch = load_schema(Path(sys.argv[1]))
    inst = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    found = validate(inst, sch)
    for err in found:
        print(f"  - {err}")
    print(f"[{'FAIL' if found else 'OK'}] {len(found)} 处不符")
    sys.exit(1 if found else 0)
