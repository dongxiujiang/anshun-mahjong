extends RefCounted
## 新版私有牌谱。记录真实发牌输入和已被权威接受的指令，重演时不改写回合内部状态。

const Protocol = preload("res://src/domain/Protocol.gd")
const Round = preload("res://src/domain/Round.gd")
const Dice = preload("res://src/runtime/DiceRoll.gd")
const Score = preload("res://src/anshun/scoring/ScoringEngine.gd")
const Dealer = preload("res://src/anshun/DealerSelection.gd")

var _data: Dictionary

func _init(number: int, dealer: int, carry: int, stock: Array, locked_dice: Dictionary) -> void:
	_data = {"variant_id": Protocol.VARIANT_ID, "rules_version": Protocol.RULES_VERSION,
		"record_version": Protocol.RECORD_VERSION, "protocol_version": Protocol.PROTOCOL_VERSION,
		"round_number": number, "dealer": dealer,
		"carry_multiplier": carry, "wall": stock.duplicate(), "dice": locked_dice.duplicate(true),
		"inputs": []}

func append(command: Dictionary) -> void:
	_data.inputs.append(command.duplicate(true))

func finish(facts: Dictionary, ledger: Dictionary, next_dealer: int) -> Dictionary:
	var record := _data.duplicate(true)
	record.facts = facts.duplicate(true)
	record.ledger = ledger.duplicate(true)
	record.next_dealer_seat = next_dealer
	record.checksum = _canonical(record).sha256_text()
	return record


func export_authority() -> Dictionary:
	return _data.duplicate(true)


func restore_authority(state: Dictionary) -> bool:
	if not state.get("inputs") is Array:
		return false
	_data = state.duplicate(true)
	return true

## 对普通 JSON 数的 int/float 表示归一。摘要用于检测文件变化，不能认证签发者。
static func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

static func replay_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return _reject("invalid_json")
	return replay(parser.data)

static func replay(record: Dictionary) -> Dictionary:
	if record.get("variant_id") != Protocol.VARIANT_ID:
		return _reject("unsupported_version")
	for entry in [["record_version", Protocol.RECORD_VERSION], ["rules_version", Protocol.RULES_VERSION], ["protocol_version", Protocol.PROTOCOL_VERSION]]:
		if not _integer(record.get(entry[0]), entry[1], entry[1]):
			return _reject("unsupported_version")
	var body := record.duplicate(false)
	body.erase("checksum")
	if record.get("checksum") != _canonical(body).sha256_text():
		return _reject("checksum")
	if not _integer(record.get("round_number"), 1, 2147483647) or not _integer(record.get("dealer"), 0, 3) or not _integer(record.get("carry_multiplier"), 1, 2):
		return _reject("opening")
	if not record.get("wall") is Array or not record.get("inputs") is Array or not record.get("facts") is Dictionary or not record.get("ledger") is Dictionary:
		return _reject("schema")
	if not _valid_dice(record.get("dice")):
		return _reject("dice")
	var round_state := Round.new()
	var faces: Array = record.dice.result
	if not round_state.start(int(record.dealer), int(faces[0]), int(faces[1]), record.wall, int(record.carry_multiplier)):
		return _reject("wall")
	for command in record.inputs:
		if not command is Dictionary or not _integer(command.get("prompt_id"), 1, 2147483647) or int(command.prompt_id) != round_state.prompt_id:
			return _reject("stale_input")
		if not _apply(round_state, command):
			return _reject("illegal_input")
	if round_state.phase != "settled":
		return _reject("incomplete")
	var facts := round_state.settlement_facts()
	if _canonical(facts) != _canonical(record.facts):
		return _reject("result_facts")
	var scored := Score.settle(facts)
	if _canonical(scored) != _canonical(record.ledger):
		return _reject("ledger")
	if not _integer(record.get("next_dealer_seat"), 0, 3) or not Dealer.candidates(scored, int(record.dealer)).has(int(record.next_dealer_seat)):
		return _reject("next_dealer")
	return {"ok": true, "facts": facts, "ledger": scored, "events": round_state.events.duplicate(true),
		"next_dealer_seat": int(record.next_dealer_seat)}

static func _apply(round_state: Round, command: Dictionary) -> bool:
	match command.get("type"):
		"begin_dealer_turn":
			return command.size() == 2 and round_state.begin_dealer_turn()
		"finish_draw_animation":
			return command.size() == 3 and _integer(command.get("seat"), 0, 3) and round_state.finish_draw_animation(int(command.seat), int(command.prompt_id))
		"submit", "timeout":
			if command.size() != 5 or not _integer(command.get("seat"), 0, 3) or not _integer(command.get("tile_id"), -1, 107) or not command.get("action") is String:
				return false
			if command.type == "timeout" and command.action not in ["pass", "discard"]:
				return false
			return round_state.submit(int(command.seat), int(command.prompt_id), command.action, int(command.tile_id))
	return false

static func _valid_dice(value: Variant) -> bool:
	if not value is Dictionary or value.get("phase") != "settled" or not _integer(value.get("roll_id"), 1, 2147483647) or not _integer(value.get("frame"), 1, 2147483647):
		return false
	if not value.get("result") is Array or value.result.size() != 2 or not value.get("poses") is Array or value.poses.size() != 2:
		return false
	for index in 2:
		if not _integer(value.result[index], 1, 6):
			return false
		var pose: Variant = value.poses[index]
		if not pose is Array or pose.size() != 7:
			return false
		for number in pose:
			if typeof(number) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(number)):
				return false
		var q := Quaternion(pose[3], pose[4], pose[5], pose[6])
		if not q.is_normalized() or (Basis(q) * Vector3(Dice.FACE_NORMALS[int(value.result[index]) - 1])).y < Dice.UPRIGHT_DOT:
			return false
	if value.has("physics") and not _valid_physics_trace(value):return false
	return true

static func _valid_physics_trace(dice:Dictionary)->bool:
	var trace:Variant=dice.physics
	if not trace is Dictionary or trace.get("parameters_version")!=Dice.TRACE_PARAMETERS_VERSION:return false
	if not trace.get("backend") is String or trace.backend.is_empty() or not trace.get("engine_version") is String:return false
	if not _integer(trace.get("ticks_per_second"),1,1000) or not trace.get("parameters") is Dictionary:return false
	for key in ["side","tray_half","gravity","mass","friction","bounce","stable_seconds","upright_dot"]:
		if not _numbers([trace.parameters.get(key)],1):return false
	if not trace.get("initial") is Array or trace.initial.size()!=2:return false
	for body in trace.initial:
		if not body is Dictionary or not _pose(body.get("pose")) or not _numbers(body.get("linear_velocity"),3) or not _numbers(body.get("angular_velocity"),3):return false
	if not trace.get("trajectory") is Array or trace.trajectory.size()<2 or not trace.get("taps") is Array:return false
	var previous:=-1
	for sample in trace.trajectory:
		if not sample is Dictionary or not _integer(sample.get("frame"),previous+1,int(dice.frame)):return false
		if not sample.get("poses") is Array or sample.poses.size()!=2 or not sample.poses.all(func(pose):return _pose(pose)):return false
		previous=int(sample.frame)
	if trace.trajectory[0].frame!=0 or previous!=int(dice.frame) or trace.trajectory.back().poses!=dice.poses:return false
	previous=-1
	for tap in trace.taps:
		if not tap is Dictionary or not _integer(tap.get("frame"),previous+1,int(dice.frame)) or not tap.get("dice") is Array or tap.dice.is_empty() or tap.dice.size()>2:return false
		var indices:=[]
		for event in tap.dice:
			if not event is Dictionary or not _integer(event.get("index"),0,1) or indices.has(event.index):return false
			if not _numbers(event.get("impulse"),3) or not _numbers(event.get("torque"),3):return false
			indices.append(event.index)
		previous=int(tap.frame)
	return true

static func _numbers(value:Variant,count:int)->bool:
	return value is Array and value.size()==count and value.all(func(number):return typeof(number) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(number)))

static func _pose(value:Variant)->bool:
	return _numbers(value,7) and Quaternion(value[3],value[4],value[5],value[6]).is_normalized()

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= minimum and value <= maximum and value == int(value)

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
