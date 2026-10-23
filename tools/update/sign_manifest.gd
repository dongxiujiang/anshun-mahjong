extends SceneTree
## Sign one update manifest with the offline RSA release key.
## Usage:
##   godot --headless --path . --script res://tools/update/sign_manifest.gd -- \
##     res://build/release/update-manifest.json build/signing/manifest_private.pem

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("用法: sign_manifest.gd -- <manifest.json> <private-key.pem>")
		quit(2)
		return
	var manifest_path := args[0]
	var key_path := args[1]
	var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary:
		push_error("无法读取清单")
		quit(1)
		return
	data.erase("signed_payload")
	data.erase("signature")
	var payload := JSON.stringify(data).to_utf8_buffer()
	var key := CryptoKey.new()
	if key.load_from_string(FileAccess.get_file_as_string(key_path)) != OK:
		push_error("无法读取签名私钥")
		quit(1)
		return
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(payload)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, hasher.finish(), key)
	if signature.is_empty():
		push_error("清单签名失败")
		quit(1)
		return
	data["signed_payload"] = Marshalls.raw_to_base64(payload)
	data["signature"] = Marshalls.raw_to_base64(signature)
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入清单")
		quit(1)
		return
	file.store_string(JSON.stringify(data, "  ", false) + "\n")
	file.close()
	print("manifest signed: ", manifest_path, " bytes=", payload.size())
	quit()
