class_name ActorPortrait
extends PanelContainer

@onready var name_label: Label = $Margin/Rows/Name
@onready var hp_bar: ProgressBar = $Margin/Rows/HP
@onready var hp_label: Label = $Margin/Rows/HPText
@onready var ac_label: Label = $Margin/Rows/AC

func set_actor(data: Dictionary) -> void:
	name_label.text = data.get("name", "--")
	hp_bar.value = float(data.get("hp_fraction", 0.0)) * 100.0
	hp_label.text = "HP %d/%d" % [data.get("hp", 0), data.get("max_hp", 0)]
	ac_label.text = "AC %d" % data.get("armor_class", 0)
