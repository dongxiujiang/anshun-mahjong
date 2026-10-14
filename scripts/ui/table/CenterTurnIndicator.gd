extends Control
## 只绘制当前出牌方向的柔光。四边权重仅在切换时 Tween，无持续 CPU 重绘。
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
var active_side := -1
var _transition: Tween
var _light: ColorRect
const LIGHT_SHADER := """
shader_type canvas_item;
uniform vec4 light_color : source_color;
uniform vec4 sides = vec4(0.0);
uniform float spread = 26.0;
void fragment() {
    vec2 p = UV * (168.0 + spread * 2.0) - vec2(spread);
    float bottom = exp(-pow(abs(p.y - 168.0) / 10.0, 2.0)) * exp(-pow(abs(p.x - 84.0) / 76.0, 4.0));
    float right = exp(-pow(abs(p.x - 168.0) / 10.0, 2.0)) * exp(-pow(abs(p.y - 84.0) / 76.0, 4.0));
    float top = exp(-pow(abs(p.y) / 10.0, 2.0)) * exp(-pow(abs(p.x - 84.0) / 76.0, 4.0));
    float left = exp(-pow(abs(p.x) / 10.0, 2.0)) * exp(-pow(abs(p.y - 84.0) / 76.0, 4.0));
    float haze = dot(vec4(bottom, right, top, left), sides) * 0.34;
    float b = exp(-pow(abs(p.y - 168.0) / 1.35, 2.0)) * step(5.0, p.x) * step(p.x, 163.0);
    float r = exp(-pow(abs(p.x - 168.0) / 1.35, 2.0)) * step(5.0, p.y) * step(p.y, 163.0);
    float t = exp(-pow(abs(p.y) / 1.35, 2.0)) * step(5.0, p.x) * step(p.x, 163.0);
    float l = exp(-pow(abs(p.x) / 1.35, 2.0)) * step(5.0, p.y) * step(p.y, 163.0);
    COLOR = vec4(light_color.rgb, clamp(haze + dot(vec4(b,r,t,l), sides) * 0.8, 0.0, 1.0));
}
"""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light = ColorRect.new()
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.position = Vector2.ONE * -UI.TURN_LIGHT_SPREAD
	_light.size = UI.CENTER_SIZE + Vector2.ONE * UI.TURN_LIGHT_SPREAD * 2.0
	var shader := Shader.new()
	shader.code = LIGHT_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("light_color", UI.TURN_LIGHT_COLOR)
	material.set_shader_parameter("spread", UI.TURN_LIGHT_SPREAD)
	material.set_shader_parameter("sides", Vector4.ZERO)
	_light.material = material
	add_child(_light)

func set_active(side: int) -> void:
	if active_side == side: return
	active_side = side
	if _transition != null: _transition.kill()
	var target := Vector4.ZERO
	if side in range(4): target[side] = 1.0
	var material := _light.material as ShaderMaterial
	if DisplayServer.get_name() == "headless":
		material.set_shader_parameter("sides", target)
	else:
		var start: Vector4 = material.get_shader_parameter("sides")
		_transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_transition.tween_method(func(value: Vector4): material.set_shader_parameter("sides", value), start, target, 0.22)

func _exit_tree() -> void:
	if _transition != null: _transition.kill()
