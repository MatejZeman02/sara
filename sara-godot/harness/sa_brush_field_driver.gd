## The `brush_field` step: a brush field registered, or replaced, from text, so
## a notebook cell can make one and the next stroke paints with it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `{"brush_field": {"name": "ripples", "source": "def brush_field(...) -> vec2:\n..."}}`
## writes *source* as `ripples.gmacs` into the folder the door names for the
## engine, `SaBrushFieldRegistry.folder_for`, `brush-fields/noise/` under the
## data root, and asks the engine to read its folder again before the step
## answers. So a field from a notebook is a painter's field like any other: the
## Texture row lists it, a preset stores it, it stays after the notebook is
## closed, and the same step sent again with a changed function replaces it.
## `"engine"` names another engine's folder, the noise brush's by default.
##
## The verdict is JSON, `SaCapture: brush_field {"ok": true, "field": "ripples",
## "label": "Ripples", "path": ...}`, or `"ok": false` with `"error"`, the
## compiler's first line naming the file and the line, which `doc.brush_field`
## in `sara.py` raises. A stroke then paints with it once a `brush` step names
## it, `{"brush": {"preset": "Grain Round", "texture_field": "ripples"}}`.
##
## Only the door's registry and folder are named here, never the engine's
## module, which reads the folder its own way.
extends RefCounted

## The engine a step names none for.
const ENGINE: StringName = &"noise"
## What a name may hold, which is what a field's id is made of.
const NAME_PATTERN: String = "^[A-Za-z0-9_]+$"


## Registers a brush field from text. Runs *spec* against *registry* and
## prints the verdict line, answering it.
static func run(registry: SaBrushFieldRegistry, spec: Variant) -> Dictionary:
    var verdict := write(registry, spec)
    print("SaCapture: brush_field %s" % JSON.stringify(verdict))
    return verdict


## Writes *spec*'s source into its engine's folder, asks the engine to read it
## and answers what the registry holds then.
static func write(registry: SaBrushFieldRegistry, spec: Variant) -> Dictionary:
    if not spec is Dictionary:
        return {"ok": false, "error": 'a brush_field step is {"name": ..., "source": ...}.'}
    var asked: Dictionary = spec
    var name := String(asked.get("name", ""))
    var source := String(asked.get("source", ""))
    var engine := StringName(String(asked.get("engine", ENGINE)))
    if not RegEx.create_from_string(NAME_PATTERN).search(name):
        return {"ok": false, "error": "a brush field's name is letters, digits and underscores, not '%s'." % name}
    if source.strip_edges().is_empty():
        return {"ok": false, "error": "the brush field '%s' has no source." % name}
    if registry == null:
        return {"ok": false, "error": "this Sara has no brush field registry."}
    var folder := SaBrushFieldRegistry.folder_for(engine)
    DirAccess.make_dir_recursive_absolute(folder)
    var path := folder.path_join(name + ".gmacs")
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return {"ok": false, "error": "%s cannot be written (%s)." % [path, error_string(FileAccess.get_open_error())]}
    file.store_string(source)
    file.close()
    registry.reread_asked.emit(engine)
    var verdict := {"ok": false, "field": name.to_lower(), "path": path}
    var taken := registry.field(engine, name.to_lower())
    if taken != null and taken.source == path:
        verdict["ok"] = true
        verdict["label"] = taken.label
        return verdict
    verdict["error"] = String(registry.refusals.get(path, "the engine did not take the field, and the log says why."))
    return verdict
