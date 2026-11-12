## The door's `text` and `font` steps, which the harness reaches through the
## roles `text_step`, `text_edit_step` and `font_step` this module registers,
## so the harness names no module.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `text` makes a text layer or edits one through the session the Text tool
## uses, so a scenario's block is the layer and the one history step a hand's
## is. `font` loads a font file, lists the families, or says which characters
## of a string a family has a glyph for. `text` with a `caret` puts the Text
## tool's caret by index, the page's `text_edit`. Each answers one line of
## JSON after its name, which a scenario reads and a script checks a layout by.
extends RefCounted

const Fonts = preload("res://modules/sara-base-modules/text/fonts/sa_text_fonts.gd")
const Session = preload("res://modules/sara-base-modules/text/edit/sa_text_session.gd")
const Recipe = preload("res://modules/sara-base-modules/text/sa_text_recipe.gd")


## Makes or edits a text layer of *document* as *spec* says: `content`, the
## text with its newlines, `at`, where the first baseline starts in document
## pixels, `font`, a family, `size`, pixels an em, `colour`, a display colour
## as `#rrggbb` or a list of floats, and `layer`, the name of a text layer to
## edit rather than a new one. A new block takes the foreground colour and the
## first shipped family unless told otherwise.
static func text_step(document: SaDocument, spec: Dictionary) -> String:
    if document == null:
        return "SaCapture: text refused, no document"
    var session: Session = null
    if spec.has("layer"):
        var named := document.get_node_or_null(NodePath(String(spec["layer"]))) as SaLayer
        if not Session.is_text(named):
            return "SaCapture: text refused, no text layer called '%s'" % spec["layer"]
        var locked := Session.refusal(named)
        if not locked.is_empty():
            return "SaCapture: text refused, %s" % locked
        session = Session.new(document, named)
    else:
        session = Session.new(document)
        var at := _vector(spec.get("at", [0.0, 0.0]))
        var family := String(spec.get("font", Fonts.DEFAULT_FAMILY))
        if not Fonts.has_family(family):
            return "SaCapture: text refused, no font called '%s'" % family
        if not session.begin_new(at, family, float(spec.get("size", Recipe.DEFAULT_SIZE)), _colour(document, spec)):
            return "SaCapture: text refused, the layer could not be made"
    var recipe := session.recipe
    var family_now := String(spec.get("font", recipe.family))
    var at_now := _vector(spec["at"]) if spec.has("at") else recipe.origin
    var colour_now := _colour(document, spec) if spec.has("colour") else recipe.paint
    recipe.set_block(
        String(spec.get("content", recipe.text)), family_now, float(spec.get("size", recipe.size)), colour_now, at_now
    )
    var layer := session.layer
    var stepped := session.commit()
    return "SaCapture: text %s" % JSON.stringify(report(layer, stepped))


## What a text layer says of itself to the door: its name, whether the step
## recorded one, and its recipe's own report, which the state dump carries too.
static func report(layer: SaLayer, stepped: bool = false) -> Dictionary:
    if not is_instance_valid(layer) or not Session.is_text(layer):
        return {"layer": "", "step": stepped}
    var said := {"layer": String(layer.name), "step": stepped}
    said.merge((layer.recipe as Recipe).report())
    return said


## Puts the Text tool's caret by character index, the `text` step with a
## `caret`, for a scenario that then
## types through the `key` step as a hand would: `layer` names a text layer
## to open, `caret` the index the caret goes before, the end of the text when
## it names none. *machine* is the canvas's tool machine, which takes the Text
## tool up. A selection waits for styled spans and is refused.
static func text_edit_step(document: SaDocument, spec: Dictionary, machine: Object) -> String:
    if document == null or machine == null:
        return "SaCapture: text refused, no document"
    if spec.has("select"):
        return "SaCapture: text refused, a selection waits for styled spans"
    if machine.get("active_tool_name") != &"text":
        machine.call("set_active_tool", &"text")
    var tool: Object = machine.get("active_tool")
    if tool == null or not tool.has_method("place_caret"):
        return "SaCapture: text refused, the Text tool is not registered"
    if spec.has("layer"):
        var named := document.get_node_or_null(NodePath(String(spec["layer"]))) as SaLayer
        var locked := Session.refusal(named) if Session.is_text(named) else ""
        if not locked.is_empty():
            return "SaCapture: text refused, %s" % locked
        if not tool.call("edit", named):
            return "SaCapture: text refused, no text layer called '%s'" % spec["layer"]
    if not tool.call("editing"):
        return "SaCapture: text refused, no block is being edited and no layer was named"
    if spec.has("caret"):
        tool.call("place_caret", int(spec["caret"]))
    return "SaCapture: text %s" % JSON.stringify({"text": tool.get("_text"), "caret": tool.get("_caret")})


## Loads, lists or asks of the fonts: `{"font": "list"}`, `{"font": {"load":
## "<path>"}}`, `{"font": {"forget": "<family>"}}` and `{"font": {"has":
## "<text>", "family": "<family>"}}`, the last answering per character whether
## the family has a glyph for it.
static func font_step(_document: SaDocument, spec: Variant) -> String:
    var asked: Dictionary = spec if spec is Dictionary else {"list": true}
    if asked.has("load"):
        var family := Fonts.load_file(String(asked["load"]))
        if family.is_empty():
            return "SaCapture: font refused, '%s' is not a font file" % asked["load"]
        return "SaCapture: font %s" % JSON.stringify({"loaded": family})
    if asked.has("forget"):
        Fonts.forget(String(asked["forget"]))
        return "SaCapture: font %s" % JSON.stringify({"forgot": String(asked["forget"])})
    if asked.has("has"):
        var font := Fonts.font_for(String(asked.get("family", Fonts.DEFAULT_FAMILY)))
        if font == null:
            return "SaCapture: font refused, no font called '%s'" % asked.get("family", "")
        var found: Array = []
        for character in String(asked["has"]):
            found.append([character, font.has_char(character.unicode_at(0))])
        return "SaCapture: font %s" % JSON.stringify({"family": font.get_font_name(), "has": found})
    return "SaCapture: font %s" % JSON.stringify({"families": Fonts.families()})


static func _vector(raw: Variant) -> Vector2:
    var pair: Array = raw if raw is Array else []
    return Vector2(float(pair[0]), float(pair[1])) if pair.size() >= 2 else Vector2.ZERO


## The step's colour in *document*'s own space, the foreground when it names
## none.
static func _colour(document: SaDocument, spec: Dictionary) -> Color:
    var raw: Variant = spec.get("colour", null)
    var shown := SaInHand.Pair.foreground()
    if raw is String:
        shown = Color.from_string(String(raw), shown)
    elif raw is Array and (raw as Array).size() >= 3:
        var c: Array = raw
        shown = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
    return document.color_space.from_display(shown) if document.color_space != null else shown
