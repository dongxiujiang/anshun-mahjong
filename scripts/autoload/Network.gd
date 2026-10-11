extends Node
## 联机入口（Autoload）：持有 NetGameNode（跨场景存活，RPC 路径两端一致 /root/Network/Net）。

signal peer_joined(peer_id)
signal peer_left(peer_id)

var mode := ""            # "host" / "client" / ""
var net_node: NetGameNode = null
var def_port := 7500

func _ready() -> void:
	net_node = NetGameNode.new()
	net_node.name = "Net"
	add_child(net_node)

## 建主机：host_auto=主机自己是否自动代打(否则由本机UI操作)，ai_fill=空位补AI
func start_host(host_auto: bool, ai_fill: bool, port: int = 0) -> bool:
	var ok := net_node.host(host_auto, ai_fill, port if port > 0 else def_port)
	if ok:
		mode = "host"
	return ok

func start_client(ip: String, port: int = 0) -> bool:
	if not net_node.client(ip, port if port > 0 else def_port):
		return false
	mode = "client"
	return true

func reset() -> void:
	mode = ""
	multiplayer.multiplayer_peer = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	net_node = NetGameNode.new()
	net_node.name = "Net"
	add_child(net_node)

func is_host() -> bool:
	return mode == "host" and multiplayer.get_unique_id() == 1
