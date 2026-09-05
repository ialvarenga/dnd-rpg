class_name CombatLog
extends RichTextLabel

func append_line(line: String) -> void:
	append_text(line + "\n")
	scroll_to_line(get_line_count())
