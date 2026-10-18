# -*- coding: utf-8 -*-
"""
麻将牌型穷举测试 - 生成所有牌型说明文档
"""

import os
from pathlib import Path

# 输出目录
output_dir = Path("test_screenshots")
output_dir.mkdir(exist_ok=True)

# 所有测试用例
test_cases = [
    {
        "name": "01_小七对_自摸",
        "concealed": ["万1", "万1", "万2", "万2", "万3", "万3", "万4", "万4", "万5", "万5", "万6", "万6", "万7", "万7"],
        "melds": [],
        "win_tile": "万7",
        "self_draw": True,
        "pattern": "小七对",
        "score": 24,
        "description": "小七对自摸，赢家每家收24分"
    },
    {
        "name": "02_小七对_点炮",
        "concealed": ["条1", "条1", "条2", "条2", "条3", "条3", "条4", "条4", "条5", "条5", "条6", "条6", "条7", "条7"],
        "melds": [],
        "win_tile": "条7",
        "self_draw": False,
        "discard_seat": 1,
        "pattern": "小七对",
        "score": 24,
        "description": "小七对点炮，放炮者支付24分"
    },
    {
        "name": "03_龙七对_自摸",
        "concealed": ["万1", "万1", "万1", "万1", "万2", "万2", "万3", "万3", "万4", "万4", "万5", "万5", "万6", "万6"],
        "melds": [],
        "win_tile": "万6",
        "self_draw": True,
        "pattern": "龙七对",
        "score": 44,
        "description": "龙七对自摸（四张万1），赢家每家收44分"
    },
    {
        "name": "04_龙七对_点炮",
        "concealed": ["筒1", "筒1", "筒2", "筒2", "筒2", "筒2", "筒3", "筒3", "筒4", "筒4", "筒5", "筒5", "筒6", "筒6"],
        "melds": [],
        "win_tile": "筒6",
        "self_draw": False,
        "discard_seat": 2,
        "pattern": "龙七对",
        "score": 44,
        "description": "龙七对点炮（四张筒2），放炮者支付44分"
    },
    {
        "name": "05_大队子_自摸",
        "concealed": ["万1", "万1", "万2", "万2", "万2", "万3", "万3", "万3", "万4", "万4", "万4", "万5", "万5", "万5"],
        "melds": [],
        "win_tile": "万1",
        "self_draw": True,
        "pattern": "大队子（对对胡）",
        "score": 14,
        "description": "大队子自摸，赢家每家收14分"
    },
]

print(f"准备生成 {len(test_cases)} 个测试用例的说明文档...")

