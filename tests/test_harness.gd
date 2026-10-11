extends RefCounted
## 测试断言收集器：把失败的断言累积起来，由调用方统一决定退出码。
##
## 为什么不用 assert()：assert 只会在 debug 构建里生效，release 构建直接跳过；
## 而且 assert 不会改变退出码，CI 里测试失败也会返回 0。
## 用法：
##     const H := preload("res://tests/test_harness.gd")
##     var t := H.new()
##     func _initialize() -> void: call_deferred("_run")
##     func _run() -> void:
##         t.expect(cond, "失败信息")
##         quit(t.finish("smoke_xxx"))

var checks := 0
var failures := 0
var _messages: Array[String] = []

func expect(condition: bool, message: String = "") -> bool:
	checks += 1
	if condition:
		return true
	failures += 1
	var text := message if message != "" else "断言失败"
	_messages.append(text)
	push_error("[FAIL] " + text)
	print("  [FAIL] " + text)
	return false

## 打印汇总并返回退出码：0=全部通过，1=有失败。
func finish(name: String) -> int:
	if failures == 0:
		print("[%s] 通过 (%d 项断言)" % [name, checks])
		# Windows 的 OS.execute 可能错解中文编码，汇总器使用 ASCII 完成标记。
		print("[%s] passed (%d checks)" % [name, checks])
		return 0
	print("[%s] 失败: %d/%d 项断言未通过" % [name, failures, checks])
	for text in _messages:
		print("  - " + text)
	return 1
