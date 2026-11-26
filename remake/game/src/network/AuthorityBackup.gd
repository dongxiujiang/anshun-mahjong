extends RefCounted
## Encrypt-then-MAC with independent random keys. The selected peer holds the
## ephemeral RSA private key in memory. LAN discovery/hello has no PKI: this
## protects against passive listeners, not an active MITM or modified successor.
static func seal(state: Dictionary, keys: PackedByteArray) -> Dictionary:
	if keys.size() != 64: return {}
	var plain := var_to_bytes(state)
	var padding := 16 - plain.size() % 16
	for index in padding: plain.append(padding)
	var crypto := Crypto.new()
	var iv := crypto.generate_random_bytes(16)
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_ENCRYPT, keys.slice(0, 32), iv) != OK: return {}
	var cipher := aes.update(plain)
	aes.finish()
	var payload := iv + cipher
	return {"payload": payload, "tag": crypto.hmac_digest(HashingContext.HASH_SHA256, keys.slice(32), payload)}

static func unseal(packet: Dictionary, private_key: CryptoKey) -> Dictionary:
	if private_key == null or not packet.get("wrapped") is PackedByteArray: return {}
	if not packet.get("payload") is PackedByteArray or not packet.get("tag") is PackedByteArray: return {}
	var crypto := Crypto.new()
	var keys := crypto.decrypt(private_key, packet.wrapped)
	var payload: PackedByteArray = packet.payload
	if keys.size() != 64 or payload.size() < 32 or payload.size() % 16 != 0: return {}
	if not crypto.constant_time_compare(packet.tag, crypto.hmac_digest(HashingContext.HASH_SHA256, keys.slice(32), payload)): return {}
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_DECRYPT, keys.slice(0, 32), payload.slice(0, 16)) != OK: return {}
	var plain := aes.update(payload.slice(16))
	aes.finish()
	var padding := int(plain[-1])
	if padding < 1 or padding > 16: return {}
	var value: Variant = bytes_to_var(plain.slice(0, plain.size() - padding))
	return value if value is Dictionary else {}
