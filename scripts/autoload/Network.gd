extends Node
## 联机入口（Autoload）：持有 NetGameNode（跨场景存活，RPC 路径两端一致 /root/Network/Net）。

signal peer_joined(peer_id)
signal peer_left(peer_id)

var mode := ""            # "host" / "client" / ""
var net_node: NetGameNode = null
var def_port := 7500
var discovery: LanDiscovery
var directory: OnlineDirectory

func _ready() -> void:
	net_node = NetGameNode.new()
	net_node.name = "Net"
	add_child(net_node)
	discovery = LanDiscovery.new()
	add_child(discovery)
	directory = OnlineDirectory.new()
	add_child(directory)

## 建主机：host_auto=主机自己是否自动代打(否则由本机UI操作)，ai_fill=空位补AI
func start_host(host_auto: bool, ai_fill: bool, port: int = 0, number: String = "0000", title: String = "麻将房间") -> bool:
	var ok := net_node.host(host_auto, ai_fill, port if port > 0 else def_port, number, title)
	if ok:
		mode = "host"
	return ok

func start_client(ip: String, port: int = 0, number: String = "", owner_token: String = "") -> bool:
	if not net_node.client(ip, port if port > 0 else def_port, number, GameConfig.player_name, owner_token):
		return false
	mode = "client"
	return true

func reset() -> void:
	if net_node != null and net_node.host_mode and net_node.game != null: net_node.game.export_replay()
	mode = ""
	discovery.stop_search()
	discovery.stop_advertise()
	multiplayer.multiplayer_peer = null
	remove_child(net_node)
	net_node.queue_free()
	net_node = NetGameNode.new()
	net_node.name = "Net"
	add_child(net_node)

func is_host() -> bool:
	return mode == "host" and multiplayer.get_unique_id() == 1
