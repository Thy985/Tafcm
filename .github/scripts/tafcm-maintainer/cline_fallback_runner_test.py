#!/usr/bin/env python3
"""cline_fallback_runner_test.py — 模型降级链 runner 守门测试

验证 cline_fallback_runner.py 的核心契约：
- 成功即停：首个模型成功 → 不尝试后续模型，model_used.json 落 provider/model/attempt
- 分类降级：rate_limit / timeout / auth 类失败 → 按 config 动作跳下一模型
- 未知失败不掩盖：unknown → fail 动作 → 不降级（真问题不得洗白）
- 尝试封顶：maxAttemptsPerRun 生效
- 缺 key 跳过：provider keySecret 对应 env 不存在 → 记日志跳过该条目
- 密钥零泄漏：stub 主动回显收到的 key，runner 输出任何位置不得出现明文 key
- prompt 变量替换：--var KEY=V 替换 {{KEY}}

纯 stdlib + tempfile。CI 入口：
    python3 .github/scripts/tafcm-maintainer/cline_fallback_runner_test.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNNER = HERE / "cline_fallback_runner.py"

SECRET_A = 'sk-SECRET-ALPHA-0123456789'
SECRET_B = 'sk-SECRET-BETA-0123456789'

STUB_CLINE = '''#!/usr/bin/env python3
"""Stub cline：行为由 STUB_PLAN 环境变量驱动（JSON：{argv0: plan}）。
plan: {"exit": int, "out": str, "auth_log": bool, "prompt_log": bool}
匹配规则：auth 子命令用 -m 的 model 名；执行子命令用上一个成功 auth 的
model（记录在 STUB_STATE 文件）。"""
import json, os, sys

state_path = os.environ['STUB_STATE']
plan = json.loads(os.environ['STUB_PLAN'])

def load_state():
    with open(state_path) as f:
        return json.load(f)

def save_state(s):
    with open(state_path, 'w') as f:
        json.dump(s, f)

args = sys.argv[1:]
st = load_state()
if args and args[0] == 'auth':
    model = args[args.index('-m') + 1]
    key = args[args.index('-k') + 1]
    p = plan.get('auth:' + model, {"exit": 0})
    if p.get('out'):
        print(p['out'].replace('KEY', key))
    if p.get('exit', 0) == 0:
        st['authed'] = model
        st.setdefault('auth_calls', []).append(model)
        # 记录 key 供测试断言泄漏（不打印）
        st.setdefault('keys', {})[model] = key
        save_state(st)
    sys.exit(p.get('exit', 0))
else:
    model = st.get('authed', '')
    st.setdefault('run_calls', []).append(model)
    # prompt 为最后一个位置参数
    prompt = args[-1] if args else ''
    st.setdefault('prompts', {})[model] = prompt
    save_state(st)
    p = plan.get('run:' + model, {"exit": 0})
    if p.get('out'):
        print(p['out'])
    if p.get('echo_key'):
        print(st.get('keys', {}).get(model, ''))
    sys.exit(p.get('exit', 0))
'''


def write_json(path: Path, obj) -> None:
    path.write_text(json.dumps(obj), encoding='utf-8')


class RunnerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        self.stub = d / 'cline'
        self.stub.write_text(STUB_CLINE, encoding='utf-8')
        self.stub.chmod(0o755)
        self.state_path = d / "state.json"
        write_json(self.state_path, {})
        self.config = d / 'models.json'
        self.prompt = d / 'prompt.txt'
        self.out = d / 'model_used.json'
        self.env = dict(os.environ)
        self.env.update({
            "STUB_STATE": str(self.state_path),
            'AGNES_TEST_KEY': SECRET_A,
            'OTHER_TEST_KEY': SECRET_B,
        })

    def tearDown(self):
        self.tmp.cleanup()

    # ---- helpers ----
    def make_config(self, plan_run=None, chain=None, max_attempts=5,
                    on_error=None, providers=None):
        cfg = {
            'providers': providers or {
                'p1': {'clineProvider': 'openai',
                       'baseUrl': 'https://p1.example/v1',
                       'keySecret': 'AGNES_TEST_KEY'},
                'p2': {'clineProvider': 'openai',
                       'baseUrl': 'https://p2.example/v1',
                       'keySecret': 'OTHER_TEST_KEY'},
            },
            'chain': chain or [
                {'provider': 'p1', 'model': 'm1'},
                {'provider': 'p2', 'model': 'm2'},
            ],
            'maxAttemptsPerRun': max_attempts,
        }
        if on_error:
            cfg['onError'] = on_error
        write_json(self.config, cfg)
        plan = {'auth:m1': {'exit': 0}, 'auth:m2': {'exit': 0}}
        for k, v in (plan_run or {}).items():
            plan[k] = v
        self.env['STUB_PLAN'] = json.dumps(plan)
        return cfg

    def run_runner(self, extra_args=()):
        self.prompt.write_text('hello prompt PR={{PR_NUM}}', encoding='utf-8')
        proc = subprocess.run(
            [sys.executable, str(RUNNER),
             '--config', str(self.config),
             '--prompt-file', str(self.prompt),
             '--output-model-file', str(self.out),
             '--cline-bin', f'{sys.executable} {self.stub}',
             '--var', 'PR_NUM=4242', *extra_args],
            capture_output=True, text=True, env=self.env, timeout=60)
        return proc

    def state(self):
        return json.loads(self.state_path.read_text(encoding='utf-8'))

    # ---- 契约 1：成功即停 ----
    def test_success_first_model_stops_chain(self):
        self.make_config()
        proc = self.run_runner()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        used = json.loads(self.out.read_text(encoding='utf-8'))
        self.assertEqual(used, {'provider': 'p1', 'model': 'm1', 'attempt': 1})
        self.assertEqual(self.state()['run_calls'], ['m1'])

    # ---- 契约 2：分类降级 ----
    def test_rate_limit_falls_back_to_next_model(self):
        self.make_config(plan_run={
            'run:m1': {'exit': 1, 'out': "error: You've reached the API "
                                         "rate limit for free users."},
        })
        proc = self.run_runner()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        used = json.loads(self.out.read_text(encoding='utf-8'))
        self.assertEqual(used, {'provider': 'p2', 'model': 'm2', 'attempt': 2})
        self.assertIn('FALLBACK', proc.stdout)
        self.assertIn('rate_limit', proc.stdout)
        self.assertEqual(self.state()['run_calls'], ['m1', 'm2'])

    def test_auth_error_falls_back(self):
        self.make_config(plan_run={
            'run:m1': {'exit': 1, 'out': 'HTTP 401 unauthorized'},
        })
        proc = self.run_runner()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(self.out.read_text())['model'], 'm2')

    def test_timeout_falls_back(self):
        self.make_config(plan_run={
            'run:m1': {'exit': 1, 'out': 'request timed out (ETIMEDOUT)'},
        })
        proc = self.run_runner()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(self.out.read_text())['model'], 'm2')

    # ---- 契约 3：未知失败不降级不掩盖 ----
    def test_unknown_failure_does_not_fall_back(self):
        self.make_config(plan_run={
            'run:m1': {'exit': 2, 'out': 'some bizarre tool error'},
        })
        proc = self.run_runner()
        self.assertEqual(proc.returncode, 1)
        self.assertNotIn('m2', self.state().get('run_calls', []))
        self.assertIn('unknown', (proc.stdout + proc.stderr).lower())
        self.assertFalse(self.out.exists())

    # ---- 契约 4：尝试封顶 ----
    def test_max_attempts_caps_fallback_chain(self):
        self.make_config(
            plan_run={
                'run:m1': {'exit': 1, 'out': '429 rate limit'},
                'run:m2': {'exit': 1, 'out': '429 rate limit'},
            },
            max_attempts=1)
        proc = self.run_runner()
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(self.state()['run_calls'], ['m1'])

    # ---- 契约 5：缺 key 跳过该条目 ----
    def test_missing_key_skips_entry(self):
        self.make_config(plan_run={
            'run:m2': {'exit': 0},
        }, providers={
            'p1': {'clineProvider': 'openai', 'baseUrl': 'https://p1/v1',
                   'keySecret': 'NO_SUCH_ENV_VAR'},
            'p2': {'clineProvider': 'openai', 'baseUrl': 'https://p2/v1',
                   'keySecret': 'OTHER_TEST_KEY'},
        })
        # p1 无 auth 失败记录时 stub auth m1 也会 exit 0——但 runner 应在
        # auth 之前因缺 key 跳过
        proc = self.run_runner()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(self.state()['run_calls'], ['m2'])
        self.assertIn('missing_key', proc.stdout)

    # ---- 契约 6：密钥零泄漏 ----
    def test_secrets_never_appear_in_output(self):
        self.make_config(plan_run={
            # stub 主动回显 key + 可分类的限流文本（否则 unknown 不降级）
            'run:m1': {'exit': 1, 'echo_key': True,
                       'out': 'upstream 429 rate limit hit'},
        })
        proc = self.run_runner()
        allout = proc.stdout + proc.stderr
        self.assertNotIn(SECRET_A, allout)
        self.assertNotIn(SECRET_B, allout)
        self.assertEqual(proc.returncode, 0)  # 降级后 m2 成功

    # ---- 契约 7：prompt 变量替换 ----
    def test_prompt_var_substitution(self):
        self.make_config()
        self.run_runner()
        prompts = self.state()['prompts']
        self.assertEqual(prompts['m1'], 'hello prompt PR=4242')

    # ---- 附加：auth 失败也按分类处理 ----
    def test_auth_command_failure_rate_limit_falls_back(self):
        self.make_config(plan_run={
            'auth:m1': {'exit': 1, 'out': '429 Too Many Requests'},
        })
        proc = self.run_runner()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(self.out.read_text())['model'], 'm2')

    # ---- 附加：链全灭 → exit 1 + 明确汇总 ----
    def test_all_chain_exhausted_fails(self):
        self.make_config(plan_run={
            'run:m1': {'exit': 1, 'out': 'rate limit'},
            'run:m2': {'exit': 1, 'out': '401 unauthorized'},
        })
        proc = self.run_runner()
        self.assertEqual(proc.returncode, 1)
        self.assertIn('ALL_CHAIN_FAILED', proc.stdout)
        self.assertFalse(self.out.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
