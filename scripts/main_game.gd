extends  Node2D

func _ready():
	print("Current scene tree:")
	_print_tree(get_tree().current_scene, 0)

func _print_tree(node: Node, indent: int) -> void:
	print("  ".repeat(indent) + str(node.name))
	for child in node.get_children():
		_print_tree(child, indent + 1)
