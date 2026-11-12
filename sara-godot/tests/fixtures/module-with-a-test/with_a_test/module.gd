# A painter's copy of a module that ships a test beside it.
extends SaModule

const Names := preload("names.gd")


func get_id() -> StringName:
    return &"d3_copy"


func get_name() -> String:
    return Names.title()


func register(_ctx: SaContext) -> void:
    pass
