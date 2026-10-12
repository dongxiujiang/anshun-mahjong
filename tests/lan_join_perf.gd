extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

class MeasuredDiscovery extends LanDiscovery:
	var packets := 0
	var slow_send := false
	func _send_to(_socket: PacketPeerUDP, _address: String, _port: int, _bytes: PackedByteArray) -> void:
		packets += 1
		if slow_send: OS.delay_usec(2000)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var scanner := MeasuredDiscovery.new()
	root.add_child(scanner)
	scanner._net = NetGameNode.new()
	scanner._net._members = {1: {}}
	scanner._advertise_interface_timer = 3600
	var socket := PacketPeerUDP.new()
	scanner._advertise_probes = [{"socket": socket, "address": "192.168.43.1", "targets": PackedStringArray(["192.168.43.2"])}]
	scanner._send_announcements(0.01)
	t.expect(scanner.packets == 8 and scanner._announce_timer == scanner.PROBE_INTERVAL, "Empty room discovery limits bursts to eight packets")
	scanner._net._members[2] = {}
	scanner._announce_timer = 0
	scanner._send_announcements(0.01)
	t.expect(scanner._announce_timer == scanner.OCCUPIED_ANNOUNCEMENT_INTERVAL, "Joined room reduces announcement traffic fivefold")
	var before := scanner.packets
	scanner._send_announcements(0.1)
	t.expect(scanner.packets == before, "Announcements do not flood every frame after join")
	scanner._net._started = true
	scanner._advertise_interface_timer = 0
	scanner._announce_timer = 0
	scanner._send_announcements(0.1)
	t.expect(scanner.packets == before and scanner._advertise_interface_timer == 0, "Playing room performs no announcements or interface enumeration")
	scanner._net._started = false
	scanner._advertise_interface_timer = 3600
	scanner.slow_send = true
	scanner._send_announcements(0.1)
	t.expect(scanner.packets == before + 1, "Slow UDP send stops current frame budget instead of blocking forty sends")
	scanner.slow_send = false
	scanner._probes = [{"socket": socket, "address": "192.168.43.1", "targets": PackedStringArray(["192.168.43.2"]), "cursor": 0}]
	scanner.slow_send = true
	before = scanner.packets
	scanner._send_probes(0.1)
	t.expect(scanner.packets == before + 1, "Client fallback scan also obeys frame budget")
	scanner._net.free()
	scanner._net = null
	scanner.free()
	var network := root.get_node("Network")
	network.discovery.search()
	t.expect(network.discovery.searching, "Search fixture starts")
	network.reset()
	t.expect(not network.discovery.searching and network.discovery._query == null and network.discovery._probes.is_empty(), "Reset releases all scanning sockets before joining a room")
	quit(t.finish("lan_join_perf"))
