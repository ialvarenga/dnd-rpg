class_name TooltipLayer
extends CanvasLayer

func show_tooltip(text: String, position: Vector2) -> void:
	$Label.text = text
	$Label.position = position
	$Label.visible = not text.is_empty()
