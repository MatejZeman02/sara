## Sara's own Czech, a module that brings one language and nothing else, the
## shape `docs/specs/languages.md` of Sara's repository gives a language.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The catalogue is a machine draft no one has reviewed yet, README.md says
## how it was made and how a reviewer takes an entry over. It is found beside
## this script rather than at a path written out, so the module reads the same
## from a user's modules folder.
extends SaModule

## The catalogue's file, beside this script. The untouched draft beside it,
## `cs.machine.po`, is never loaded.
const CATALOGUE_FILE := "cs.po"

## The locale the catalogue is for, which its `Language` line names.
const LOCALE := "cs"


func get_id() -> StringName:
    return &"language-cs"


func get_name() -> String:
    return "Czech"


func register(ctx: SaContext) -> void:
    ctx.register_translation(catalogue_path())


## The catalogue's path, beside wherever this script was loaded from.
func catalogue_path() -> String:
    return (get_script() as Script).resource_path.get_base_dir().path_join(CATALOGUE_FILE)
