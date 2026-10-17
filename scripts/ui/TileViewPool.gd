extends RefCounted

## 对象池，用于管理 TileView 实例的创建和回收

var _pool: Array[TileView] = []
const MAX_POOL_SIZE := 200  # 最大缓存数量

func acquire() -> TileView:
	"""从对象池获取一个 TileView 实例。"""
	if _pool.is_empty():
		return TileView.new()
	return _pool.pop_back()

func release(tile: TileView) -> void:
	"""将 TileView 实例归还到对象池。"""
	if _pool.size() >= MAX_POOL_SIZE:
		tile.queue_free()
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
		tile.queue_free()
	_pool.clear()
