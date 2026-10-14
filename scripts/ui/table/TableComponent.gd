extends RefCounted
## 组件通过弱引用访问牌桌协调器，避免节点与组件互相持有而泄漏。

var _table_ref: WeakRef
var table:
	get: return _table_ref.get_ref()

func _init(view: Control) -> void:
	_table_ref = weakref(view)
