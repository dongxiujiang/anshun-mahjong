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

