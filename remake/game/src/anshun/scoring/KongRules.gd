extends RefCounted

static func is_post_kong_discard(discard: Dictionary) -> bool:
	return discard.get("after_kong", false) and discard.get("kong_kind", "") in ["concealed", "add_kong"]

static func kind(meld: Dictionary) -> String:
	if meld.kind == "add_kong":
		return "add_kong"
	return "concealed" if meld.get("concealed", false) else "exposed"

static func has_self_kong(melds: Array) -> bool:
	for meld in melds:
		if meld.kind in ["kong", "add_kong"] and kind(meld) != "exposed":
			return true
	return false

static func has_kong(melds: Array) -> bool:
	return melds.any(func(meld): return meld.kind in ["kong", "add_kong"])
