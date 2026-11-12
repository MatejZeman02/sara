## A module that brings one language and nothing else, Czech: the shape a language module takes, proved
## with a catalogue the suites install.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, and
## `ui/settings/pages/tests/test_a_module_registers_a_translation.gd` registers it
## by hand into registries of its own.
##
## The catalogue is found beside this script rather than at a path written
## out, so the module reads the same from a user's modules folder.
extends SaModule

## The catalogue's file, beside this script.
const CATALOGUE_FILE := "cs.po"

## The locale the catalogue is for, which its `Language` line names.
const LOCALE := "cs"


func get_id() -> StringName:
    return &"language-fixture"


func get_name() -> String:
    return "Language Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_translation(catalogue_path())


## The catalogue's path, beside wherever this script was loaded from.
func catalogue_path() -> String:
    return (get_script() as Script).resource_path.get_base_dir().path_join(CATALOGUE_FILE)
