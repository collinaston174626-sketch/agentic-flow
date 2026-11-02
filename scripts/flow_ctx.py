#!/usr/bin/env python3
"""Замер заполнения контекстного окна субагента /flow по его транскрипту.

Использование:
  flow_ctx.py <agent-id>          — конкретный агент (id из результата Agent / SendMessage)
  flow_ctx.py --self <FLOW_MARK>  — свой транскрипт: тот, в чьём промпте есть уникальная
                                    метка FLOW_MARK, которую оркестратор вписал в задание
Вывод одной строкой: ctx_tokens=<n> compaction=<bool> level=<ok|handoff> file=<path>
Порог: переменная FLOW_CTX_HANDOFF (по умолчанию 300000).
Код возврата: 0 — ok, 2 — handoff (пора передавать работу преемнику), 3 — не найден/не разобран.
Берётся последнее НЕнулевое usage (строка ошибки 429 имеет нулевое usage и не считается).
"""
import glob, json, os, sys

HANDOFF = int(os.environ.get("FLOW_CTX_HANDOFF", "300000"))
PAT = os.path.expanduser("~/.claude/projects/*/*/subagents/agent-*.jsonl")

def find(args):
    files = glob.glob(PAT)
    if args and args[0] == "--self":
        if len(args) < 2:
            return None
        mark = args[1]
        hit = []
        for f in files:
            try:
                with open(f, errors="ignore") as fh:
                    head = fh.read(400000)
                if mark in head:
                    hit.append(f)
            except OSError:
                pass
        files = hit
    elif args:
        files = [f for f in files if f.endswith(f"agent-{args[0]}.jsonl")]
    files.sort(key=os.path.getmtime)
    return files[-1] if files else None

def measure(path):
    usage, comp = {}, False
    with open(path, errors="ignore") as fh:
        for line in fh:
            if "compact_boundary" in line or '"isCompactSummary":true' in line:
                comp = True
            if '"usage"' not in line:
                continue
            try:
                m = json.loads(line).get("message") or {}
            except Exception:
                continue
            u = m.get("usage") if isinstance(m, dict) else None
            if u and (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                      + u.get("cache_creation_input_tokens", 0)) > 0:
                usage = u
    if not usage:
        return None, comp
    return (usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0)
            + usage.get("cache_creation_input_tokens", 0)), comp

def main():
    f = find(sys.argv[1:])
    if not f:
        print("ctx_tokens=unknown compaction=unknown level=unknown file=NOT_FOUND"); return 3
    n, comp = measure(f)
    if n is None:
        print(f"ctx_tokens=unknown compaction={comp} level=unknown file={f}"); return 3
    level = "handoff" if n >= HANDOFF else "ok"
    print(f"ctx_tokens={n} compaction={comp} level={level} file={f}")
    return 2 if level == "handoff" else 0

if __name__ == "__main__":
    sys.exit(main())
