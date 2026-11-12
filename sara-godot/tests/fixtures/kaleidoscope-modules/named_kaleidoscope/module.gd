# tests/fixtures/kaleidoscope-modules/named_kaleidoscope/module.gd
#
# A copy whose filter keeps a global class name, which the loader refuses with a
# sentence in the Modules menu. The folder carries a
# `.gdignore`, so the editor never files the name below as the project's own.
#
# SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule


func get_id() -> StringName:
    return &"named_kaleidoscope"


func register(_ctx: SaContext) -> void:
    pass
