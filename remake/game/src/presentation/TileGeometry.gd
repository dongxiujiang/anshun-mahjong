extends RefCounted
## Measured local bounds of every mesh in the approved classic tile library.
## X is width, Y thickness, Z length when face-up. Tests compare against all real meshes.
const WIDTH := 1.0
const LENGTH := 1.34
const THICKNESS := 0.62
const BOUNDS := AABB(Vector3(-0.5, -0.31, -0.67), Vector3(1.0, 0.62, 1.34))

static func transformed_bounds(transform: Transform3D) -> AABB:
	var result := AABB(transform * BOUNDS.position, Vector3.ZERO)
	for index in 8: result = result.expand(transform * BOUNDS.get_endpoint(index))
	return result

static func tile_bounds(pitch_degrees: float = 0.0, yaw_degrees: float = 0.0) -> AABB:
	return transformed_bounds(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_degrees)), Vector3.ZERO))

static func opposite_kong_bounds() -> AABB:
	var result := transformed_bounds(Transform3D(Basis.IDENTITY, Vector3(-WIDTH, 0, 0)))
	for x in [0.0, WIDTH]: result = result.merge(transformed_bounds(Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))))
	return result.merge(transformed_bounds(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 0, -(LENGTH + WIDTH) / 2))))

static func prototype_bounds(kind: String, hand_pitch: float = 90.0) -> AABB:
	if kind in ["public_front", "public_left"]: return opposite_kong_bounds()
	return tile_bounds(hand_pitch if kind in ["hand", "draw"] else 0.0)

static func prototype_tiles(kind: String, hand_pitch: float = 90.0) -> Array:
	if kind not in ["public_front", "public_left"]:
		return [Transform3D(Basis(Vector3.RIGHT, deg_to_rad(hand_pitch if kind in ["hand", "draw"] else 0)), Vector3.ZERO)]
	return [Transform3D(Basis.IDENTITY, Vector3(-WIDTH, 0, 0)), Transform3D.IDENTITY,
		Transform3D(Basis.IDENTITY, Vector3(WIDTH, 0, 0)),
		Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 0, -(LENGTH + WIDTH) / 2))]
