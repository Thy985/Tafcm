"""Contract Sync — 最小版（ROADMAP 3.10.2，D1/R12）。

Feature Capability Matrix（L2，S0-S5 标注）↔ contracts/*.json 一致性机器强制：
- 规则 1（反向）：Matrix 标 S0 的能力 ⊆ contract.s0_unsupported
  （Matrix 已标不支持的，contract 必须声明——漏声明 = 漂移 ERROR）
- 规则 2（正向）：Matrix 标 S≥4 的能力 ∉ contract.s0_unsupported
  （Matrix 已支持的，contract 不得标为不支持——误声明 = 漂移 ERROR）
- 规则 3（闭合）：contract.s0_unsupported 需有 Matrix 依据；
  Matrix 无独立条目的额外能力（如 serializer=Fidelity 子维度）→ WARN

输出：{status, errors[], warnings[], matrix_s0, matrix_supported, contracts}
exit：0=一致（可含 WARN）/ 1=漂移 ERROR
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from ..harness.contract import repo_root


def matrix_path() -> Path:
    return repo_root() / "docs" / "FEATURE-CAPABILITY-COVERAGE-MATRIX-v1.md"


def _norm(name: str) -> str:
    """命名归一化：小写 + 空格/连字符 → 下划线（Matrix 名 ↔ contract s0 名匹配）。"""
    return name.strip().lower().replace(" ", "_").replace("-", "_")


def parse_matrix_scores(text: str) -> dict[str, int]:
    """从 Matrix 表格行提取 {能力名(归一化): S级}。

    行格式：`| 类别 | 能力名 | ✅/❌/⚠️ | 行数 | 出处 | **Sx** | 判定 |`
    → 取第 2 列（能力名）+ 倒数第 2 列（**Sx**）。S0* 视为 S0。
    能力名归一化（小写/空格→下划线）以便与 contract s0 名匹配。
    """
    scores: dict[str, int] = {}
    for line in text.splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 6:
            continue
        name = _norm(cells[1])
        s_match = re.search(r"\*\*S(\d)\*?\*\*", line)
        if not s_match:
            continue
        level = int(s_match.group(1))
        scores[name] = level
    return scores


def matrix_s0(scores: dict[str, int]) -> list[str]:
    return [k for k, v in scores.items() if v == 0]


def matrix_supported(scores: dict[str, int]) -> list[str]:
    return [k for k, v in scores.items() if v >= 4]


def _check_corpus_assets(root: Path) -> tuple[list[str], list[str]]:
    """3.11.5 corpus 资产 schema 校验（评审：Defect Attribution Contract）。

    校验 tests/verification_cases/**/*.json：
      - JSON 有效
      - owner_capability 必填
      - cross_capabilities / required_for 为数组
      - required_for 应包含 owner_capability（owned 语义）
      - defect_attribution（若存在）：owner / affected_capabilities /
        evidence_owner / repair_target 必填
    """
    errors: list[str] = []
    warnings: list[str] = []
    cases_dir = root / "tests" / "verification_cases"
    if not cases_dir.is_dir():
        return errors, warnings
    for cf in sorted(cases_dir.rglob("*.json")):
        rel = str(cf.relative_to(root))
        try:
            data = json.loads(cf.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            errors.append(f"{rel}: JSON 无效 ({e})")
            continue
        cap = data.get("capability", "?")
        owner = data.get("owner_capability")
        if not owner:
            errors.append(f"[corpus:{rel}] owner_capability 必填（Defect Attribution）")
        cross = data.get("cross_capabilities")
        if cross is not None and not isinstance(cross, list):
            errors.append(f"[corpus:{rel}] cross_capabilities 应为数组")
        req = data.get("required_for")
        if not isinstance(req, list):
            errors.append(f"[corpus:{rel}] required_for 应为数组")
        elif owner and owner not in req:
            errors.append(
                f"[corpus:{rel}] required_for 应包含 owner_capability='{owner}'（owned 语义）"
            )
        # defect_attribution（Real Defect 资产必填；Synthetic 资产可无）
        da = data.get("defect_attribution")
        if da is not None:
            for fld in ("owner", "affected_capabilities", "evidence_owner", "repair_target"):
                if not da.get(fld):
                    errors.append(f"[corpus:{rel}] defect_attribution.{fld} 必填")
            if not isinstance(da.get("affected_capabilities"), list):
                errors.append(f"[corpus:{rel}] defect_attribution.affected_capabilities 应为数组")
            if cap not in (da.get("affected_capabilities") or []):
                warnings.append(
                    f"[corpus:{rel}] defect_attribution.affected_capabilities 未含 capability='{cap}'"
                )
    return errors, warnings


def check_contract_sync() -> dict[str, Any]:
    """执行 contract sync 校验 → 一致性报告。"""
    root = repo_root()
    mp = matrix_path()
    if not mp.is_file():
        return {
            "status": "error",
            "message": f"matrix not found: {mp}",
            "errors": [f"matrix missing: {mp}"],
            "warnings": [],
        }

    scores = parse_matrix_scores(mp.read_text(encoding="utf-8"))
    m_s0 = matrix_s0(scores)
    m_sup = matrix_supported(scores)

    contracts_dir = root / "contracts"
    contract_files = sorted(contracts_dir.glob("*.json")) if contracts_dir.is_dir() else []

    errors: list[str] = []
    warnings: list[str] = []
    contracts_report: dict[str, Any] = {}

    for cf in contract_files:
        try:
            data = json.loads(cf.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            errors.append(f"{cf.name}: JSON 无效 ({e})")
            continue
        cap = data.get("capability", cf.stem)
        s0 = data.get("s0_unsupported", [])
        contracts_report[cap] = {"s0_unsupported": s0, "file": cf.name}

        # 规则 1（反向）：Matrix S0 必须被 contract 声明
        # （仅对 Matrix 有该能力名的情况；能力名映射见下）
        for m_name in m_s0:
            if _capability_of_matrix_name(m_name) == cap:
                if m_name not in s0:
                    errors.append(
                        f"[{cap}] Matrix S0 '{m_name}' 未在 contract.s0_unsupported 声明"
                    )

        # 规则 2（正向）：Matrix S≥4 不得被 contract 标为不支持
        for m_name in m_sup:
            if _capability_of_matrix_name(m_name) == cap:
                if m_name in s0:
                    errors.append(
                        f"[{cap}] Matrix S≥4 '{m_name}' 被 contract 误标为 s0_unsupported"
                    )

        # 规则 3（闭合）：contract s0 需有 Matrix 依据（S0 或 Matrix 无该能力名）
        for item in s0:
            if item in m_s0:
                continue
            if item not in scores:
                warnings.append(
                    f"[{cap}] s0 '{item}' 在 Matrix 无独立条目（额外能力边界，需人工确认）"
                )
            else:
                errors.append(
                    f"[{cap}] s0 '{item}' 在 Matrix 标 S{scores[item]}（非 S0）——漂移"
                )

        # 3.11.5 Meta-Validation（评审：四套 schema 自洽校验）

        # M1: s0 声明数 vs unknown_max 自洽（s0 全声明时 unknown_max 必须 >= s0 数，
        #     否则 verify 必然 overflow 误报 fail——3.10 Re-Audit 暴露）
        s0_count = len(s0)
        unknown_max = int((data.get("completion_policy") or {}).get("unknown_max", 0))
        if unknown_max > 0 and s0_count > unknown_max:
            errors.append(
                f"[{cap}] schema 不自洽: s0_unsupported({s0_count}) > "
                f"completion_policy.unknown_max({unknown_max})——verify 必 overflow fail"
            )

        # M2: fingerprint v2 schema（评审：fingerprint_version 保护历史 failure 集）
        fp = data.get("fingerprint") or {}
        if fp.get("version") != 2:
            errors.append(f"[{cap}] fingerprint.version 应为 2（当前 {fp.get('version')}）")
        fp_fields = fp.get("fields") or []
        if not {"capability", "failing_check", "failure_class", "evidence_signature"} <= set(fp_fields):
            errors.append(f"[{cap}] fingerprint.fields 缺四层字段（当前 {fp_fields}）")

        # M3: evidence_profile 级别合法
        _EP_LEVELS = {"required", "recommended", "conditional", "release-gate"}
        ep = data.get("evidence_profile") or {}
        for k, v in ep.items():
            if v not in _EP_LEVELS:
                errors.append(
                    f"[{cap}] evidence_profile[{k}]='{v}' 非法级别（应为 "
                    f"{sorted(_EP_LEVELS)}）"
                )

        # M4: evidence_strength 枚举合法（achieved / minimum_required ∈ enum）
        es = data.get("evidence_strength") or {}
        es_enum = set(es.get("enum") or [])
        for field in ("achieved", "minimum_required"):
            val = es.get(field)
            if isinstance(val, list):
                bad = [x for x in val if x not in es_enum]
                if bad:
                    errors.append(f"[{cap}] evidence_strength.{field} 非法值: {bad}")
            elif val is not None and val not in es_enum:
                errors.append(f"[{cap}] evidence_strength.{field}='{val}' 不在 enum {sorted(es_enum)}")

    # 3.11.5 corpus 资产 schema 校验（Defect Attribution Contract）
    corpus_errors, corpus_warnings = _check_corpus_assets(root)
    errors.extend(corpus_errors)
    warnings.extend(corpus_warnings)

    # 额外：能力名与 Matrix 的映射（block/inline 分类下的具体名）
    return {
        "status": "error" if errors else "ok",
        "matrix_s0": m_s0,
        "matrix_supported": m_sup,
        "contracts": contracts_report,
        "errors": errors,
        "warnings": warnings,
    }


# Matrix 能力名 → capability 契约的映射（最小版：s0 三项 + 额外项）。
# 归一化后匹配：Matrix 名经 _norm（小写/空格→下划线）后与 contract s0 名对齐。
_MATRIX_TO_MARKDOWN = {
    "autolink",
    "footnote",
    "definition_list",
    "indented_code",
    "raw_html_块",
}


def _capability_of_matrix_name(name: str) -> str:
    """Matrix 能力名归属的 capability（最小版：按名称约定映射，入参已归一化）。"""
    if name in _MATRIX_TO_MARKDOWN:
        return "markdown"
    return name  # 其他能力名与 capability 同名（近似）


def render_sync_report(result: dict[str, Any]) -> str:
    lines = [
        f"contract sync: status={result['status']}",
        f"  matrix S0       : {result['matrix_s0']}",
        f"  matrix S≥4      : {result['matrix_supported']}",
        f"  contracts       : {list(result['contracts'])}",
    ]
    if result["errors"]:
        lines.append("  errors:")
        for e in result["errors"]:
            lines.append(f"    ✗ {e}")
    if result["warnings"]:
        lines.append("  warnings:")
        for w in result["warnings"]:
            lines.append(f"    ⚠ {w}")
    if not result["errors"] and not result["warnings"]:
        lines.append("  无漂移（Matrix ↔ contracts 一致）")
    return "\n".join(lines)
