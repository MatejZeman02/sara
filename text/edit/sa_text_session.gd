## One edit of a text layer, from the click that starts it to the commit that
## makes it one history step, shared by the Text tool and the door's `text`
## step so a hand and a scenario make the same layer and the same step.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The layer is drawn while it is typed.** A new block's layer goes into the
## document at the first click, above the active layer as Add Layer puts one,
## and every key redraws the tiles it touched, so the painter sees the letters
## land. The history hears nothing until the commit: a new layer is then one
## Add Text step whose undo takes the layer out, and an edit of a layer that
## was there is one Edit Text step holding the recipe's JSON either side, never
## a chunk. A new block committed empty leaves nothing behind.
##
## **The layer is made through the drawn layer's door** rather than the type
## registry, which a tool is not handed: its type id, its schema for the
## document's space and `SaDrawnLayer.attach` with this module's recipe, the
## three things the registry's `apply_to` does for a drawn type. A file opened
## later rebinds it through the registry, where `module.gd` registered it.
extends RefCounted

const Recipe = preload("res://modules/sara-base-modules/text/sa_text_recipe.gd")

## The layer type a text layer is, as `module.gd` registers it.
const TYPE := &"text"
## The history's rows for a new block and for an edit of one.
const ADD_STEP := "Add Text"
const EDIT_STEP := "Edit Text"
## What a locked text layer says to a click on its letters and to the door,
## the sentence the transform, Rasterize and a merge say of a lock.
const LOCKED := "'%s' is locked. Unlock it in the Layers docker first."

## The layer the session edits, and its recipe.
var layer: SaLayer = null
var recipe: Recipe = null
## Whether the layer was made by this session and is not in the history yet.
var fresh: bool = false

var _document: SaDocument = null
## The recipe's JSON when the session began, for an edit of a layer that was
## there.
var _before: Dictionary = {}
## The layer that was active before a new block's, given the brush back when
## the block is committed empty.
var _was_active: SaLayer = null


## A session on *edited*, a text layer already in *document*, made active, or
## on nothing until [method begin_new] makes a new block's layer. A locked
## layer is not opened, so its words stay as the painter locked them.
func _init(document: SaDocument, edited: SaLayer = null) -> void:
    _document = document
    if edited == null or not is_text(edited) or edited.is_locked:
        return
    layer = edited
    recipe = edited.recipe as Recipe
    _before = recipe.to_json()
    document.set_active_layer(edited)


## Makes a new text layer above the active one, its block empty and starting at
## *at* in *family* at *em* pixels in *colour*, and answers whether it could.
func begin_new(at: Vector2, family: String, em: float, colour: Color) -> bool:
    if _document == null or layer != null:
        return false
    var made := SaLayer.new()
    made.name = "Text"
    made.layer_type = TYPE
    made.schema = SaFieldSpec.schema_for_space(_document.color_space)
    _was_active = _document.active_layer
    var index := _was_active.get_index() + 1 if _was_active != null else _document.get_child_count()
    made.group = SaLayerStack.parent_of(_was_active)
    _document.add_child(made)
    _document.move_child(made, mini(index, _document.get_child_count() - 1))
    var made_recipe := SaDrawnLayer.attach(made, Recipe) as Recipe
    if made_recipe == null:
        _document.remove_child(made)
        made.free()
        return false
    _document.set_active_layer(made)
    layer = made
    recipe = made_recipe
    fresh = true
    recipe.set_block("", family, em, colour, at)
    return true


## The sentence an edit of *edited* is turned away with, translated, or an
## empty string when nothing keeps it shut.
static func refusal(edited: SaLayer) -> String:
    if edited != null and edited.is_locked:
        return TranslationServer.translate(LOCKED) % edited.name
    return ""


## Whether *candidate* is a text layer this module draws.
static func is_text(candidate: SaLayer) -> bool:
    return candidate != null and candidate.recipe != null and candidate.recipe.get_script() == Recipe


## Whether the session's layer is still in the document.
func in_document() -> bool:
    return (
        layer != null
        and is_instance_valid(layer)
        and not layer.is_queued_for_deletion()
        and _document != null
        and is_instance_valid(_document)
        and layer.get_parent() == _document
    )


## How far a click may land outside a block's lines and still be on it, in
## document pixels.
const HIT_MARGIN := 6.0


## The box a click is on a text layer in: every line's whole height, from the
## top of its ascent to the foot of its descent, joined with the glyphs'
## bounds and grown by [constant HIT_MARGIN]. The glyphs' bounds alone left the
## gap under a line with no descenders to a click that made a new layer.
static func hit_box(text_layer: SaLayer) -> Rect2:
    var block := text_layer.recipe as Recipe
    var layout := block.laid_out()
    var box := Rect2(block.bounds())
    var first := not box.has_area()
    for l in layout.starts.size():
        var from := layout.caret_at(layout.starts[l])
        var to := layout.caret_at(layout.starts[l] + layout.lengths[l])
        var line := Rect2(block.origin + from.position, Vector2(to.position.x - from.position.x, from.size.y))
        box = line if first else box.merge(line)
        first = false
    return box.grow(HIT_MARGIN)


## The topmost visible text layer of *document* whose box, see [method hit_box],
## holds *at*, or null.
static func text_layer_at(document: SaDocument, at: Vector2) -> SaLayer:
    if document == null:
        return null
    for i in range(document.get_child_count() - 1, -1, -1):
        var candidate := document.get_child(i) as SaLayer
        if is_text(candidate) and candidate.visible and hit_box(candidate).has_point(at):
            return candidate
    return null


## Lays the block out as *said*, keeping its family, size, colour and place,
## and redraws what changed. Nothing is recorded.
func show(said: String) -> void:
    if recipe != null and in_document():
        recipe.set_block(said, recipe.family, recipe.size, recipe.paint, recipe.origin)


## The block in *family* at *em* pixels in *colour*, the Font and Size rows or
## the painter's colour moved while it is typed.
func restyle(family: String, em: float, colour: Color) -> void:
    if recipe != null and in_document():
        recipe.set_block(recipe.text, family, em, colour, recipe.origin)


## Ends the session as one history step, and answers whether it left one. A
## new block with no text takes its layer out again and leaves none. A block
## whose layer has left the document commits no step.
func commit() -> bool:
    if layer == null or _document == null:
        return false
    if not in_document():
        if not fresh and not _before.is_empty() and is_instance_valid(layer) and layer.recipe != null:
            SaDrawnLayer.restore(layer, _before)
        layer = null
        return false
    var kept := layer
    layer = null
    if fresh:
        if recipe.text.strip_edges().is_empty():
            _document.remove_child(kept)
            kept.queue_free()
            if _was_active != null and is_instance_valid(_was_active) and _was_active.get_parent() == _document:
                _document.set_active_layer(_was_active)
            return false
        kept.name = recipe.title()
        SaLayerOps.new(_document).commit_added(ADD_STEP, [kept])
        return true
    var after := recipe.to_json()
    if after == _before:
        return false
    var step := SaDrawnLayer.Step.new(kept, _before, after)
    _document.history.commit_pair(EDIT_STEP, step.redo, step.undo, step.bytes())
    _document.modified = true
    return true
