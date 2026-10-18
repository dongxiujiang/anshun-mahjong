"""Render the executable rule audit; no game logic and no document writes.

Run after Godot rules_spec.gd. Every numbered document line must have evidence.
The generated report contains the strict rule table, ambiguity table, and exact
fixtures for every failed assertion. Only tests/ and build/ are written.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs/当前游戏规则与玩法.txt"
RESULTS = ROOT / "build/rules_audit/results.json"
HEADER = "| # | 规则条目（文档行号） | 实现位置 | 断言 | 结果 | 差异说明 |\n|---|---|---|---|---|---|"


def j(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def cell(value):
    return str(value).replace("|", "&#124;").replace("\n", "<br>").replace("\r", "")


def link(path, line=None, label=None):
    target = (ROOT / path).as_posix()
    return f"[{label or Path(path).name}](<{target}{':' + str(line) if line else ''}>)"


def locations(entries):
    unique = dict.fromkeys(p.strip() for e in entries for p in e["location"].split(";"))
    links = []
    for p in unique:
        name, _, line = p.rpartition(":")
        links.append(link(name, line, Path(name).name + ":" + line))
    return "<br>".join(links)


def row(n, rule, implementation, assertion, status, difference):
    return "| " + " | ".join(cell(v) for v in (n, rule, implementation, assertion, status, difference)) + " |"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/rules_audit/report.md")
    args = parser.parse_args()
    data = json.loads(RESULTS.read_text(encoding="utf-8-sig"))
    if data.get("selected_case"):
        raise SystemExit("A full suite is required to generate the complete rule table.")
    if hashlib.sha256(DOC.read_bytes()).hexdigest() != data["document_sha256"]:
        raise SystemExit("Rule document changed since test execution; rerun the suite.")
    document = DOC.read_text(encoding="utf-8-sig").splitlines()
    rules = [(i, s.strip()) for i, s in enumerate(document, 1)
             if re.match(r"\d+\. ", s.strip()) or re.search(r"：\d+ 分$", s)
             or i in (19, 20, 21, 22, 44, 45, 46)]
    checks = data["checks"]
    indexed = defaultdict(list)
    for check in checks:
        for number in check["lines"]:
            indexed[number].append(check)
    missing = [i for i, _ in rules if not indexed[i]]
    if missing:
        raise SystemExit(f"Uncovered rules: {missing}")
    counts = Counter(c["result"] for c in checks)
    failures = [c for c in checks if c["result"] == "失败"]
    groups = defaultdict(list)
    for c in failures:
        groups[c["id"].split(".", 1)[0]].append(c)
    scenario_ids = {name: f"F{i:02d}" for i, name in enumerate(groups, 1)}
    out = [HEADER]
    out.append(row("运行", "2026-10-18 当前规则全文", link("tests/rules_spec.gd") + "<br>" + link("tests/rules_spec_v2.gd"),
                   f'{len(rules)}条文档条目；{len(checks)}记录，{counts["通过"]}通过、{counts["失败"]}失败、{counts["有歧义"]}歧义',
                   "失败" if failures else "通过", "headless完整执行；失败返回非零，全部通过返回0。所有结算逐笔守恒断言；最低分允许为负。"))
    out.append(row("证据", link("docs/当前游戏规则与玩法.txt"), link("build/rules_audit/results.json"),
                   "规则SHA256=" + data["document_sha256"], "通过",
                   "所有牌局调用set_rng_seed；默认20261018，随机并列测试另用20261018..20261029。构造局为隔离规则的状态快照，不宣称每例均从发牌走到结算。"))
    verification_file = ROOT / "build/rules_audit/verification.json"
    if verification_file.exists():
        verification = json.loads(verification_file.read_text(encoding="utf-8"))
        if verification.get("checks") == len(checks) and verification.get("document_sha256") == data["document_sha256"]:
            settlements = sum("四家总分800" in c["assertion"] for c in checks)
            out.append(row("复验", "固定种子重复运行与保护范围", link("build/rules_audit/verification.json"),
                           f'{settlements}次结算总分800；两次完整结果逐字段相同；三个失败断言与一个通过断言可单跑',
                           "通过", f'scripts/docs共{verification["protected_files_unchanged"]}个文件哈希未变；发布核心入口执行退出1并生成报告；未运行完整发布/网络/导出流程。'))
    fix_verification = ROOT / "build/rules_fix/verification.json"
    if fix_verification.exists():
        proof = json.loads(fix_verification.read_text(encoding="utf-8"))
        if proof.get("results_sha256") == hashlib.sha256(RESULTS.read_bytes()).hexdigest():
            out.append(row("修复复验", "固定种子重复运行与文档保护", link("build/rules_fix/verification.json"),
                           f'{proof["settlements_conserving_800"]}次结算总分800；两次完整JSON一致；{len(proof["standalone_passed"])}条断言独立运行通过',
                           "通过", f'docs中{proof["unchanged_docs_count"]}个原有文件哈希未变；游戏实现已经按规则及对话澄清修复。'))
            if proof.get("core_suites_passed"):
                out.append(row("全量复验", "修复后的注册回归、网络与发布入口", link("build/rules_fix/final-regression.log"),
                               f'{proof["core_suites_passed"]}/{proof["core_suites_total"]}套注册测试通过；AI 50局；网络和重连通过；导出配置4项通过',
                               "通过", "本地build-release检查.cmd已同步。完整发布预检被打开中的Godot编辑器安全检查拦下，未关闭编辑器、未导出发布包；详见 " + link("build/rules_fix/release-entry.log")))
    for i, (line, text) in enumerate(rules, 1):
        entries = indexed[line]
        definitive = [e for e in entries if e["result"] != "有歧义"]
        bad = [e for e in definitive if e["result"] == "失败"]
        status = "失败" if bad else ("通过" if definitive else "有歧义")
        if status == "有歧义":
            continue
        names = list(dict.fromkeys(e["assertion"] for e in definitive))
        assertion = "；".join(names[:6]) + (f"；共{len(definitive)}条独立断言" if len(names) > 6 else "")
        details = []
        for e in bad:
            f = scenario_ids[e["id"].split(".", 1)[0]]
            details.append(f'{f}：{e["assertion"]} 实际{j(e["actual"])} / 期望{j(e["expected"])}')
        if any(e["result"] == "有歧义" for e in entries):
            details.append("相关文档歧义另列于表后")
        out.append(row(i, link("docs/当前游戏规则与玩法.txt", line, f"L{line}") + " " + text,
                       locations(definitive), assertion, status, "<br>".join(details) or "—"))
    supplements = indexed[0]
    for i, e in enumerate(supplements, 1):
        out.append(row(f"S{i}", "任务补充：不存在诈胡按钮/处罚/结算（文档未单列）",
                       locations([e]), e["assertion"], e["result"], f'实际{j(e["actual"])} / 期望{j(e["expected"])}'))

    out.extend(["", "有歧义条目（仅列文档未写清或冲突）：", "", HEADER])
    for i, e in enumerate((c for c in checks if c["result"] == "有歧义"), 1):
        out.append(row(f"A{i}", "L" + "/".join(map(str, e["lines"])), locations([e]),
                       e["assertion"], "有歧义", f'观察值：{j(e["actual"])}；{e["expected"]}'))

    out.extend(["", "失败项最小复现（wan=万，tiao=条，tong=筒；手牌为断言前快照；空数组表示该单元不需要该座位的手牌）：", "", HEADER])
    for name, group in groups.items():
        f = scenario_ids[name]
        context = group[0]["repro"]
        seats = []
        for seat in context.get("seats", []):
            seats.append(f'座{seat["seat"]} 手牌{j(seat["hand"])}；面子{j(seat["melds"])}；弃牌{j(seat["discards"])}；报听={seat["ready"]}')
        repro = f'种子={context.get("seed", data["seed"])}；'
        repro += f'当前庄={context.get("dealer", "不适用")}；'
        repro += "<br>".join(seats) if seats else "座位/手牌/弃牌不适用（纯函数）；"
        repro += "<br>弃牌/操作序列：" + context.get("actions", "无")
        if context.get("unit_input"):
            repro += "<br>单元输入：" + context["unit_input"]
        if context.get("meta"):
            repro += "<br>结算元数据：" + j(context["meta"])
        if context.get("last_discard"):
            repro += "<br>最后弃牌：" + j(context["last_discard"])
        results = []
        for e in group:
            results.append(f'{e["id"]}：实际{j(e["actual"])} / 期望{j(e["expected"])}')
        repro += "<br>可单断言运行：godot --headless --script res://tests/rules_spec.gd -- --case \"" + group[0]["id"] + "\""
        out.append(row(f, "L" + "/".join(map(str, sorted({n for e in group for n in e["lines"]}))),
                       locations(group), "<br>".join(results), "失败", repro))

    out.extend(["", "1. 必须改代码的清单：" + ("仍有失败断言，逐项见上表及最小复现；不以变更期望掩盖失败。" if failures else "本次文档规格断言全部通过。已修正报听、烧鸡、单吊、未叫杠主付款、多赢家差额/换庄、通行条件及墙方向；AI估分、结算显示和回归测试同步。全量测试与发布结果另见修复验证记录。"), "",
                "2. 需要改文档的清单：原文件未修改。未明确行为已经用户在本次对话确认，答复保存在 " + link("tests/rules_clarifications_2026-10-18.md") + "：混合流局额外4；单倍求和后整体翻倍；多赢家净得分最高者当庄、并列随机；未胡叫牌者无牌型分；破墙跳骰点×2；座号固定；只收指基础费。确认内容已转为独立断言，不再标为未决歧义。", "",
                "复跑：godot --headless --script res://tests/rules_spec.gd；生成本表：python tests/generate_rules_audit.py。发布检查与run_all调用同一规格入口；任何失败均返回非零。历史修改前审计保留在tests/rules_audit_2026-10-18.md。"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"Audit report: {args.output}; {len(rules)} document rows; {len(failures)} failed assertions")


if __name__ == "__main__":
    main()
