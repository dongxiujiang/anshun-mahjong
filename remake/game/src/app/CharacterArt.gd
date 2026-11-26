extends RefCounted
## Portrait IDs follow the voice registry; voice selection remains independent.
const Packs = preload("res://src/audio/VoicePacks.gd")
const ROOT := "res://assets/characters/voice-portraits-v1/"
static var _portraits := {}
static var _avatars := {}

static func portrait(id: int) -> Texture2D:
	var index := clampi(id, 1, Packs.ORDER.size())
	if not _portraits.has(index):
		var path: String = ROOT + Packs.ORDER[index - 1] + ".png"
		if ResourceLoader.exists(path):
			_portraits[index] = load(path)
	return _portraits.get(index)

static func title(id: int) -> String:
	return Packs.LABELS[Packs.ORDER[clampi(id, 1, Packs.ORDER.size()) - 1]]

static func avatar(id: int) -> Texture2D:
	var index := clampi(id, 1, Packs.ORDER.size())
	if _avatars.has(index):
		return _avatars[index]
	var source := portrait(index)
	if source == null:
		return null
	var image := source.get_image()
	if image == null:
		return source
	if image.is_compressed():
		image.decompress()
	var w := image.get_width()
	var h := image.get_height()
	var step := maxi(2, int(w / 96))
	var low := Vector2i(w, h)
	var high := Vector2i.ZERO
	# Frame the head and shoulders using opaque content, ignoring transparent margins and glow.
	for y in range(0, int(h * 0.72), step):
		for x in range(0, w, step):
			if image.get_pixel(x, y).a < 0.65:
				continue
			low = low.min(Vector2i(x, y))
			high = high.max(Vector2i(x + step, y + step))
	if high.x <= low.x or high.y <= low.y:
		_avatars[index] = source
		return source
	var pad := maxi(4, int(w / 64))
	var region := Rect2i(low, high - low).grow(pad).intersection(Rect2i(Vector2i.ZERO, Vector2i(w, h)))
	var result := AtlasTexture.new()
	result.atlas = source
	result.region = Rect2(region)
	result.filter_clip = true
	_avatars[index] = result
	return result
