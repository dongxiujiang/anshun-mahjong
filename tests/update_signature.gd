extends SceneTree
## Offline manifest signature must reject tampering and accept the pinned key.
const H := preload("res://tests/test_harness.gd")
const PAYLOAD := "eyJzY2hlbWEiOjIuMCwidGVzdCI6dHJ1ZSwidmVyc2lvbiI6IjEuNC4xOSJ9"
const SIGNATURE := "F6+UAfOIsSZ0PD2CHOyz9xqrv20+u6pMh4T45MRywN3WxyiVRI6m7lC5IBkvX+xr8SPOz85HMgLJwcnTYrxYK7OLKp6SlLu4FVrjnlxsEq+7ZOhNy5DjY/KsXqHT1Jqxf5KFBrJnfAIATFxBHfJ3DGcQHJweLVbeJXG2T1xCOwTSGtadPY2ZX+2+4vP67h8wgHxUydGiQ3de8INEQyqcs0srUtuOgWA8Va0qnEpK/iJ4VZyqObvLkwgTznrrTknx0G6X09QskloHGZFfpFbzisNvNSvA8hoj/VIWWbstRcz9D4WVV7Xl6/XZaW1aAXetXpWS7FLFGsMpR6DSmD/fy3+YFsmxWGV/RjYMkZX6X4cChvuSjMpEA8Xa+UG4c3HzvR3+MM5ceqScr3nk/S2u83w6sY0CM8TiwYvKAcf8XiqvfxW2Vb2SbMc5p8uUvSBEox/4NOvMAIZ7tkkTSNXRdOZuIIY50rtwug2lX9+LqR9ZxafO1auzl1t1w4dOAPXE"
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var manager = root.get_node("UpdateManager")
	var public_key := str(ProjectSettings.get_setting("updates/manifest_public_key", ""))
	var data: Dictionary = manager.verify_manifest_payload(PAYLOAD, SIGNATURE, public_key)
	t.expect(int(data.get("schema", 0)) == 2 and str(data.get("version", "")) == "1.4.19", "signed manifest verifies against the pinned key")
	t.expect(manager.verify_manifest_payload(PAYLOAD + "x", SIGNATURE, public_key).is_empty(), "tampered signed payload is rejected")
	t.expect(manager.verify_manifest_payload(PAYLOAD, SIGNATURE, "").is_empty(), "missing public key is rejected")
	await H.quit_cleanly(self, t.finish("update_signature"))
