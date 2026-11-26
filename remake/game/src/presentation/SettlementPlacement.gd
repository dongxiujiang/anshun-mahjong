extends RefCounted
## Screen rectangles strictly inside the projected play area, excluding remaining walls and flip tiles.
static func candidates(poly: PackedVector2Array, obstacles: Array) -> Array:
	if poly.size()<3:return []
	var bounds:=Rect2(poly[0],Vector2.ZERO)
	for point in poly:bounds=bounds.expand(point)
	var result:=[]
	for top in 8:
		for bottom in range(top+1,9):
			var y0:float=lerpf(bounds.position.y,bounds.end.y,top/8.0)+5
			var y1:float=lerpf(bounds.position.y,bounds.end.y,bottom/8.0)-5
			var upper:=_span(poly,y0);var lower:=_span(poly,y1)
			if upper.x>upper.y or lower.x>lower.y:continue
			var left:=maxf(upper.x,lower.x)+5;var right:=minf(upper.y,lower.y)-5
			if right-left>200 and y1-y0>60:result.append(Rect2(left,y0,right-left,y1-y0))
	for obstacle in obstacles:
		var next:=[]
		for rect in result:
			if not rect.intersects(obstacle):next.append(rect);continue
			for clipped in [Rect2(rect.position,Vector2(obstacle.position.x-rect.position.x,rect.size.y)),Rect2(Vector2(obstacle.end.x,rect.position.y),Vector2(rect.end.x-obstacle.end.x,rect.size.y)),Rect2(rect.position,Vector2(rect.size.x,obstacle.position.y-rect.position.y)),Rect2(Vector2(rect.position.x,obstacle.end.y),Vector2(rect.size.x,rect.end.y-obstacle.end.y))]:
				if clipped.size.x>200 and clipped.size.y>60:next.append(clipped)
		result=next;result.sort_custom(func(a,b):return a.get_area()>b.get_area())
		if result.size()>48:result.resize(48)
	return result
static func _span(poly: PackedVector2Array, y: float) -> Vector2:
	var left:=INF;var right:=-INF
	for index in poly.size():
		var a:=poly[index];var b:=poly[(index+1)%poly.size()]
		if is_equal_approx(a.y,b.y):continue
		if y>=minf(a.y,b.y) and y<=maxf(a.y,b.y):
			var x:=lerpf(a.x,b.x,(y-a.y)/(b.y-a.y));left=minf(left,x);right=maxf(right,x)
	return Vector2(left,right)
