#!/usr/bin/env python3
"""contract_minicheck 的自证测试。

存在理由：写前校验器是"账本/闸口不得写入未声明字段"这条红线的执行者。
它自己没被测试过，就等于红线只写在纸上。这里既测"该过的能过"，
也测"该拦的每类都拦得住"（非恒真）。
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

from contract_minicheck import validate  # noqa: E402

SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "required": ["name", "count"],
    "additionalProperties": False,
    "properties": {
        "name": {"type": "string", "pattern": "^[a-z-]+$"},
        "count": {"type": "integer", "minimum": 0, "maximum": 5},
        "kind": {"enum": ["a", "b", None]},
        "items": {"type": "array", "minItems": 1, "maxItems": 2,
                  "items": {"type": "string"}},
        "nested": {"$ref": "#/definitions/inner"},
    },
    "definitions": {
        "inner": {
            "type": "object",
            "required": ["ok"],
            "additionalProperties": False,
            "properties": {"ok": {"type": "boolean"}},
        }
    },
}


def errors(instance, schema=SCHEMA):
    return validate(instance, schema, schema)


class AcceptTest(unittest.TestCase):
    def test_valid_minimal(self):
        self.assertEqual(errors({"name": "ab-cd", "count": 3}), [])

    def test_null_in_enum_accepted(self):
        self.assertEqual(errors({"name": "ab", "count": 0, "kind": None}), [])

    def test_ref_and_array_accepted(self):
        self.assertEqual(errors({
            "name": "ab", "count": 5,
            "items": ["x", "y"],
            "nested": {"ok": True},
        }), [])


class RejectTest(unittest.TestCase):
    def test_missing_required(self):
        self.assertTrue(any("required" in e for e in errors({"name": "ab"})))

    def test_smuggled_field_rejected(self):
        found = errors({"name": "ab", "count": 1, "from_llm": "yes"})
        self.assertTrue(any("additionalProperties" in e for e in found), found)

    def test_bad_type_rejected(self):
        self.assertTrue(errors({"name": 12, "count": 1}))

    def test_bool_is_not_integer(self):
        """True 是 int 子类，若不加排除就会把 bool 当数字放过——枚举/阈值字段常踩。"""
        self.assertTrue(errors({"name": "ab", "count": True}))

    def test_out_of_enum_rejected(self):
        self.assertTrue(any("枚举" in e for e in
                            errors({"name": "ab", "count": 1, "kind": "c"})))

    def test_out_of_range_rejected(self):
        self.assertTrue(errors({"name": "ab", "count": 9}))

    def test_pattern_violation_rejected(self):
        self.assertTrue(errors({"name": "AB CD", "count": 1}))

    def test_min_items_rejected(self):
        self.assertTrue(any("minItems" in e for e in
                            errors({"name": "ab", "count": 1, "items": []})))

    def test_max_items_rejected(self):
        self.assertTrue(any("maxItems" in e for e in
                            errors({"name": "ab", "count": 1, "items": ["a", "b", "c"]})))

    def test_nested_additional_properties_rejected(self):
        found = errors({"name": "ab", "count": 1, "nested": {"ok": True, "extra": 1}})
        self.assertTrue(any("additionalProperties" in e for e in found), found)

    def test_error_path_points_at_the_field(self):
        """报错必须定位到具体路径，否则 CI 日志无法用于修。"""
        found = errors({"name": "ab", "count": 1, "nested": {"ok": "not-bool"}})
        self.assertTrue(any("$.nested.ok" in e for e in found), found)

    def test_root_array_reports_index(self):
        found = errors({"name": "ab", "count": 1, "items": ["a", 2]})
        self.assertTrue(any("$.items[1]" in e for e in found), found)


class RealSchemaTest(unittest.TestCase):
    """对仓库真实契约跑一遍，确认解析器能吃 draft-07 的这些写法。"""

    def test_gate_schema_rejects_empty_object(self):
        gate_schema = Path(SCRIPTS).parent.parent / "schemas" / "gate-result.schema.json"
        import json
        schema = json.loads(gate_schema.read_text(encoding="utf-8"))
        found = validate({}, schema, schema)
        self.assertTrue(found, "空对象必须不符合 gate 契约")
        self.assertTrue(any("eligible" in e for e in found))


if __name__ == "__main__":
    unittest.main(verbosity=2)
