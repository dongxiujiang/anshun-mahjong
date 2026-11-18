"""Run the original graphical clock and room teardown in a traced disposable checkout."""
from pathlib import Path
import sys

here = Path(__file__).resolve().parent
if len(sys.argv) != 3:
    raise SystemExit("usage: python run_clock.py STAGED_PROJECT GODOT")
stage = Path(sys.argv[1]).resolve()
# Fail closed if the staged script/RPC source lacks a required trace marker.
for path, token in (
    ("scripts/ui/GameTable.gd", "gate_after_draw"),
    ("scripts/ui/table/v2/TableV2.gd", "sort_finish"),
    ("scripts/online/NetGameNode.gd", "ack_recv"),
    ("scripts/core/RoundState.gd", "[clk-host] first_draw"),
    ("server/RoomServer.gd", "phase/pause/waiters"),
    ("tests/online_opening_clock.gd", "[clk-client] ms="),
):
    if token not in (stage / path).read_text("utf-8"):
        raise SystemExit("Missing staged opening trace: " + path)
harness = stage / "tests/run_network.py"
src = harness.read_text("utf-8")
anchor = '            assert code == 200 and data == {"rooms": []}, "Opening clock test leaves no active room"'
if src.count(anchor) != 1:
    raise SystemExit("Clock block changed")
# Run the first online gate with the existing exception, timeout and finally handling.
src = src.replace(anchor, anchor + "\n            return")
scope = {"__file__": str(harness), "__name__": "clock_trace_harness"}
exec(compile(src, str(harness), "exec"), scope)
scope["run"](sys.argv[2], False, "online", True)


# This matrix member must exhibit the complete handoff in addition to the ordinary clock assertions.
import os
import re
if os.environ.get("CLOCK_FORCE_DROP") == "yes":
    def ordered(lines, patterns):
        rows = iter(lines.splitlines())
        for pattern in patterns:
            if not any(re.search(pattern, row) for row in rows):
                raise AssertionError("Missing ordered opening milestone: " + pattern)
    logs = list((stage / "build/room-server").glob("*.log"))
    if len(logs) != 1:
        raise AssertionError("Expected one dedicated room")
    ordered(logs[0].read_text(errors="replace"), [
        r"force_disconnect .* wall=56 steps=0 paused=true",
        r"retained_gap .* retained=true holds=true paused=true members=0 wall=56 steps=0",
        r"replacement .* authenticated=true same_seat=true new_peer=true waiter=true wall=56 steps=0",
        r"ack_recv .* round_ok=true session_ok=true member=true waiter=true count=1",
        r"resume .* phase=2",
        r"first_draw .* wall=55",
    ])
    ordered((stage/"build/online_opening_clock.log").read_text(errors="replace"), [
        r"\[clk-client\] reconnect .* attempt=0",
        r"snapshot .* phase=playing initialized=false has_draw=false",
        r"gate_after_draw .* same_session=true mode=client",
        r"ack_send .* round=1",
        r"first action at .*opening busy=false",
    ])
    print("[ok] authenticated opening recovery holds 56 tiles until rendered acknowledgement, then draws to 55", flush=True)

