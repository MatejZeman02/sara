## The `layer` step's `duplicate_to`: a layer or a group of the document in
## front copied into another open document, `SaLayerDuplicateTo`'s copy, as
## Layer > Duplicate To makes it.
##
##     {"layer": {"duplicate_to": "spring.sad", "of": "Spring",
##                "under": "Seasons", "replace": true}}
##
## `duplicate_to` names the target as the `front` step does, the name the
## `documents` step answers or a surface id such as `document_2`, which tells
## two copies of one file apart. `of` is the layer or group copied, a name or an
## index from the bottom as `read_pixels` counts, and the active layer without
## it. `under` is a group of the target the copy goes on top of, and the top of
## the stack without it. `replace` takes the target's node of the copied one's
## name at that place out, with everything inside it, and stands the copy where
## it stood, as one undo step in the target.
##
## The answer is `SaCapture: layer {...}`, as the rest of the `layer` step's:
## `copied`, the copies' names top first, `into`, the target's name,
## `replaced`, the name taken out or empty, and `missing`, a sentence for each
## effect layer whose input the target has no layer for. A refusal is
## `{"error": ...}`, and the door raises it. The document in front stays in
## front, so the next step still acts on the source.
class_name SaLayerDuplicateToStep
extends RefCounted


## Runs the step from *front* over the documents the running scene holds, and
## answers the line the harness prints.
static func run(front: SaDocument, spec: Dictionary) -> String:
    var target: Variant = _target(Engine.get_main_loop() as SceneTree, String(spec.get("duplicate_to", "")))
    if target is String:
        return _line({"error": target})
    var into: SaDocument = target
    var source: Variant = SaScenarioPixels.layer_of(front, spec.get("of"))
    if source is String:
        return _line({"error": "%s, so nothing was copied." % source})
    var under: SaLayer = null
    if spec.get("under") != null:
        var group: Variant = SaScenarioPixels.layer_of(into, spec["under"])
        if group is String:
            return _line({"error": "%s in %s, so nothing was copied." % [group, SaDocumentFiles.display_name(into)]})
        under = group
    var answer := SaLayerDuplicateTo.new(front, into).write(source, under, bool(spec.get("replace", false)))
    if not answer.has("error"):
        answer["into"] = SaDocumentFiles.display_name(into)
    return _line(answer)


## The open document *asked* names, or a sentence saying why none.
static func _target(tree: SceneTree, asked: String) -> Variant:
    var held: Object = tree.current_scene.get("documents") if tree != null and tree.current_scene != null else null
    if not held is SaDocuments:
        return "there are no open documents to copy into."
    var found: Array[SaSurface] = []
    var names: Array[String] = []
    for surface: SaSurface in (held as SaDocuments).surfaces:
        var named := SaDocumentFiles.display_name(surface.get_document())
        names.append("%s (%s)" % [named, surface.id])
        if named == asked or String(surface.id) == asked:
            found.append(surface)
    if found.size() != 1:
        var why := "no open document" if found.is_empty() else "%d open documents" % found.size()
        return "%s is %s, the open ones being %s." % [asked, why, ", ".join(names)]
    return found[0].get_document()


static func _line(answer: Dictionary) -> String:
    return "SaCapture: layer %s" % JSON.stringify(answer)
