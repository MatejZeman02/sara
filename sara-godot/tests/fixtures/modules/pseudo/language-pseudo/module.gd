## The test language, `en_XA`: every message of Sara made about 40% longer in
## accented Latin and Cyrillic letters between `‹` and `›`, so a label a longer
## language would cut shows cut.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The catalogue beside this script is written by
## `sara-godot/scripts/write_pseudo.py` and never by hand. The module sits one
## folder down, under `pseudo/`, so a scenario can name that folder with
## `--modules-dir=res://tests/fixtures/modules/pseudo` and load this module
## alone, with none of the other fixtures' dockers and pages in its shots. A
## run with the whole fixtures folder finds it too, in the grouped layout. No
## ordinary launch sees it, so no painter is offered it.
extends SaModule

## The catalogue's file, beside this script.
const CATALOGUE_FILE := "en_XA.po"


func get_id() -> StringName:
    return &"language-pseudo"


func get_name() -> String:
    return "Pseudo Language"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_translation(catalogue_path())


## The catalogue's path, beside wherever this script was loaded from.
func catalogue_path() -> String:
    return (get_script() as Script).resource_path.get_base_dir().path_join(CATALOGUE_FILE)
