extends RefCounted

## 对象池，用于管理 TileView 实例的创建和回收

var _pool: Array[TileView] = []
## 极端满桌面约 477 张：牌墙108 + 手牌/摸牌56 + 弃牌152 +
## 红色区96 + 碰杠64 + 翻牌1。留出余量后稳定复用整桌节点。
const MAX_POOL_SIZE := 512

func acquire() -> TileView:
	"""从对象池获取一个 TileView 实例。"""
	if _pool.is_empty():
		return TileView.new()
	return _pool.pop_back()

func release(tile: TileView) -> void:
	"""将 TileView 实例归还到对象池。"""
	if _pool.size() >= MAX_POOL_SIZE:
		if tile.is_inside_tree():
			tile.queue_free()
		else:
			tile.free()
		return
	
	# 重置 TileView 状态
	tile.reset()
	
	# 从场景树中移除
	if tile.get_parent():
		tile.get_parent().remove_child(tile)
	
	# 归还到池中
	_pool.append(tile)

func clear() -> void:
	"""清空对象池。"""
	for tile in _pool:
		if not is_instance_valid(tile): continue
		if tile.is_inside_tree():
			tile.queue_free()
		else:
			# 回收节点已经从场景树移除；直接释放可避免它们随池对象
			# 一起失去引用后变成 CanvasItem 泄漏。
			tile.free()
	_pool.clear()
