#!/usr/bin/env python3
"""cline_fallback_runner.py — Cline 模型降级链 runner（单一真相：models.json）

tafcm-maintainer.yml 与 cline-pr-review.yml 共用。按配置链逐个尝试
provider/model：auth → run；失败按 error-signature 分类决定是否降级。

设计红线（2026-10-03 治理规划 F 项加固，与 Human Owner 对齐）：
- **失败分类降级**：rate_limit / timeout / auth → 跳下一模型；
  unknown → 直接 FAIL——真问题不得被降级链洗成"今天恰好过了"。
  触发降级必须打印 `FALLBACK: ... class=<类别>`，夜间日志可归因。
- **密钥零泄漏**：key 只经 argv 传给 cline，runner 输出（含透传的 cline
  输出）一律对已知 key 值做 redact。
- **尝试封顶**：maxAttemptsPerRun 限制单次调用总尝试数。
- 最终生效模型写入 --output-model-file（JSON），供 report/日志归因。

用法：
    python3 cline_fallback_runner.py --config .agent/tafcm-maintainer/models.json \
        --prompt-file .tmp/prompt.txt --output-model-file .tmp/model_used.json \
        [--var PR_NUM=42] [--cline-bin cline]

退出码：0 = 某模型成功；1 = 失败（含 unknown 直接失败、链耗尽）。
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

DEFAULT_SIGNATURES = {
    'rate_limit': ['rate limit', 'rate_limit', '429', 'quota',
                   'token plan'],
    'timeout': ['timed out', 'timeout', 'etimedout', 'econnreset',
                'connection reset'],
    'auth': ['401', '403', 'unauthorized', 'invalid api key',
             'authentication', 'invalid key'],
}
DEFAULT_ON_ERROR = {
    'rate_limit': 'next',
    'timeout': 'next',
    'auth': 'next',
    'missing_key': 'next',
    'unknown': 'fail',
}
REDACTED = '***REDACTED***'
TAIL_LINES = 80


def _split_bin(spec: str) -> list:
    """--cline-bin 拆分。Windows 下 shlex.posix 会把反斜杠当转义吃掉，
    故本机退化为空格拆分（测试 tmp 路径无空格）。"""
    if os.name == 'nt':
        return spec.split()
    return shlex.split(spec)


def classify(text: str, signatures: dict) -> str:
    low = text.lower()
    for bucket in ('rate_limit', 'auth', 'timeout'):
        for sig in signatures.get(bucket, []):
            if sig in low:
                return bucket
    return 'unknown'


def redact(text: str, secrets: list) -> str:
    for s in secrets:
        if s:
            text = text.replace(s, REDACTED)
    return text


def apply_vars(prompt: str, vars_: dict) -> str:
    for k, v in vars_.items():
        prompt = prompt.replace('{{%s}}' % k, v)
    return prompt


def run_streamed(cmd: list, secrets: list) -> tuple:
    """执行并透传输出（redact 后），返回 (exit_code, tail_text)。"""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True,
                            bufsize=1)
    tail = []
    for line in proc.stdout:
        print(redact(line.rstrip('\n'), secrets), flush=True)
        tail.append(line)
        if len(tail) > TAIL_LINES:
            tail.pop(0)
    proc.wait()
    return proc.returncode, ''.join(tail)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--config', required=True)
    ap.add_argument('--prompt-file', required=True)
    ap.add_argument('--output-model-file', required=True)
    ap.add_argument('--cline-bin', default='cline',
                    help='cline 可执行命令，可含参数前缀（测试用 '
                         '"python stub.py"）')
    ap.add_argument('--var', action='append', default=[],
                    help='KEY=VALUE，替换 prompt 中的 {{KEY}}')
    args = ap.parse_args()

    cfg = json.loads(Path(args.config).read_text(encoding='utf-8'))
    providers = cfg['providers']
    chain = cfg['chain']
    max_attempts = int(cfg.get('maxAttemptsPerRun', len(chain)))
    signatures = {**DEFAULT_SIGNATURES, **cfg.get('signatures', {})}
    on_error = {**DEFAULT_ON_ERROR, **cfg.get('onError', {})}

    prompt = apply_vars(
        Path(args.prompt_file).read_text(encoding='utf-8'),
        dict(v.split('=', 1) for v in args.var))

    cline_prefix = _split_bin(args.cline_bin)

    known_secrets: list = []
    cap = min(len(chain), max_attempts)
    for attempt in range(1, cap + 1):
        entry = chain[attempt - 1]
        provider_name, model = entry['provider'], entry['model']
        pcfg = providers[provider_name]
        tag = f'{provider_name}/{model}'

        key = os.environ.get(pcfg['keySecret'], '')
        if not key:
            print(f'FALLBACK: {tag} class=missing_key '
                  f'(env {pcfg["keySecret"]} 未注入)')
            if on_error.get('missing_key', 'next') != 'next':
                return 1
            continue
        if key not in known_secrets:
            known_secrets.append(key)

        auth_cmd = cline_prefix + ['auth', '-p',
                    pcfg['clineProvider'], '-k', key, '-m', model]
        if pcfg.get('baseUrl'):
            auth_cmd += ['-b', pcfg['baseUrl']]
        rc, out = run_streamed(auth_cmd, known_secrets)
        if rc != 0:
            bucket = classify(out, signatures)
            print(f'FALLBACK: {tag} auth failed class={bucket}')
            if on_error.get(bucket, 'fail') != 'next':
                print(f'FAIL: auth class={bucket} 不允许降级')
                return 1
            continue

        rc, out = run_streamed(
            cline_prefix + ['--auto-approve', 'true', prompt],
            known_secrets)
        if rc == 0:
            print(f'MODEL_USED={tag} attempt={attempt}')
            Path(args.output_model_file).write_text(
                json.dumps({'provider': provider_name, 'model': model,
                            'attempt': attempt}), encoding='utf-8')
            return 0
        bucket = classify(out, signatures)
        print(f'FALLBACK: {tag} run failed class={bucket}')
        if on_error.get(bucket, 'fail') != 'next':
            print(f'FAIL: run class={bucket} 不允许降级（未知失败不得掩盖）')
            return 1

    print('ALL_CHAIN_FAILED: 降级链耗尽或封顶，最后类别见上方 FALLBACK 行')
    return 1


if __name__ == '__main__':
    sys.exit(main())
