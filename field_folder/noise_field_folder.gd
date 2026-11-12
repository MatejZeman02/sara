## The noise brush's fields of the painter's own: one `.gmacs` file a field in
## the door's folder for the engine, read, registered and read again when a
## file changes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A file is a field, named by the file.** Each `.gmacs` file in
## `SaBrushFieldRegistry.folder_for("noise")`, `brush-fields/noise/` under the
## data root, holds the function the door's contract names, and is registered
## through `SaContext.register_brush_field` as a module's field is (rule 6),
## with the file as its own kernel. Its id is the file's name, lower case with
## every character an id cannot hold read as an underscore, which a preset
## stores in `texture_field`, so the Texture row lists it after the shipped
## three.
##
## **A header may name it.** Comment lines at the top of the file, before the
## first line that is not one, are read for two words:
##
##     # Field: Ripples
##     # Number: Period, 2, 64, 12
##     # Number: Contrast, 0, 4, 1
##
## `Field` is the Texture row's label, the file's name when there is none, and
## each `Number` is one of the function's three numbers in order, its label,
## its range and its default. A field naming fewer has the rest as plain rows,
## A, B and C over nought to one at a half. The numbers are kept on the
## settings under keys [method number_key] makes, so a preset carries them.
##
## **One context a file, so a reload replaces a field.** Each file registers
## through a context of its own, the module's id and the file's name, so a
## changed file's field is dropped by that context's removal alone and the new
## one registered in its place. The door drops the old import with it and keeps
## the new text under the same name, and `noise_own_field.gd` caches a pass by
## the field's instance, so the new field, a new instance, is built a pass of
## its own and the old instance's is never asked for again.
##
## **Read again whenever a stroke starts**, by the state's `lay_field`, and
## when the window takes the focus back, so a field saved in an editor beside
## Sara paints at the next stroke and is listed in the Texture row on the way
## back. A file is read whole and compared by its hash, a handful of small files
## that cost far less than a frame, and a file whose text has not moved is left
## as registered. The door's `brush_field` step asks for a read at once.
##
## **A file that does not take is passed over** with one line through
## `SaProblems`, the door's for a kernel that does not compile, which names the
## file and glslang's first error, or this one's for a name another field holds,
## and the other files' fields stay. It is not tried again until its text moves.
extends RefCounted

const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")

## What every number key starts with, which the settings read as one of these
## fields' numbers rather than a property of their own.
const NUMBER_PREFIX: String = "field_number_"
## The numbers a field has, the contract's three.
const NUMBER_COUNT: int = 3
## The rows of a field whose header names no numbers.
const PLAIN_LABELS: Array[String] = ["A", "B", "C"]
const PLAIN_LOW: float = 0.0
const PLAIN_HIGH: float = 1.0
const PLAIN_DEFAULT: float = 0.5
## The header's two words.
const FIELD_WORD: String = "field:"
const NUMBER_WORD: String = "number:"
## How many steps a number's slider has across its range.
const SLIDER_STEPS: float = 100.0


## What the top of one file says: the field's label and its numbers' rows.
class Header:
    extends RefCounted

    var label: String = ""
    var specs: Array[SaOptionSpec] = []
    var defaults: PackedFloat32Array = PackedFloat32Array()
    var keys: Array[StringName] = []

    ## Reads *text*'s leading comments for the field called *field_id*, whose
    ## file is called *stem*.
    func _init(text: String, field_id: String, stem: String) -> void:
        label = stem.capitalize()
        var numbers: Array[PackedStringArray] = []
        for raw in text.replace("\r\n", "\n").split("\n"):
            var line := raw.strip_edges()
            if line.is_empty():
                continue
            if not line.begins_with("#"):
                break
            var said := line.trim_prefix("#").strip_edges()
            var word := said.to_lower()
            if word.begins_with(FIELD_WORD):
                label = said.substr(FIELD_WORD.length()).strip_edges()
            elif word.begins_with(NUMBER_WORD) and numbers.size() < NUMBER_COUNT:
                var parts := PackedStringArray()
                for part in said.substr(NUMBER_WORD.length()).split(","):
                    parts.append(part.strip_edges())
                numbers.append(parts)
        for index in NUMBER_COUNT:
            var parts: PackedStringArray = numbers[index] if index < numbers.size() else PackedStringArray()
            _add(field_id, index, parts)

    ## The number at *index*: its key, its row and its default, from *parts*,
    ## the label, the low end, the high end and the default, or a plain row.
    func _add(field_id: String, index: int, parts: PackedStringArray) -> void:
        var name := parts[0] if parts.size() > 0 and not parts[0].is_empty() else PLAIN_LABELS[index]
        var low := parts[1].to_float() if parts.size() > 1 and parts[1].is_valid_float() else PLAIN_LOW
        var high := parts[2].to_float() if parts.size() > 2 and parts[2].is_valid_float() else PLAIN_HIGH
        if high <= low:
            low = PLAIN_LOW
            high = PLAIN_HIGH
        var fallback := parts[3].to_float() if parts.size() > 3 and parts[3].is_valid_float() else (low + high) * PLAIN_DEFAULT
        var key := key_for(field_id, index)
        var spec := SaOptionSpec.make_float(
            key,
            name,
            low,
            high,
            (high - low) / SLIDER_STEPS,
            {
                "decimals": 2,
                "bar": false,
                "advanced": true,
                "tooltip": "The field's number %s, which its file reads as numbers.%s." % [PLAIN_LABELS[index], "xyz"[index]]
            }
        )
        keys.append(key)
        specs.append(spec)
        defaults.append(clampf(fallback, low, high))

    ## The settings key of the number at *index* of the field *field_id*.
    static func key_for(field_id: String, index: int) -> StringName:
        return StringName("%s%s_%d" % [NUMBER_PREFIX, field_id, index + 1])


## One file as it was last read: its text's hash, and the context its field is
## registered under, or null when it did not take.
class Entry:
    extends RefCounted

    var digest: String = ""
    var context: SaContext = null

    func _init(text_digest: String, registered_under: SaContext) -> void:
        digest = text_digest
        context = registered_under

    ## Drops the field this file registered, which drops the door's import of it.
    func drop() -> void:
        if context != null:
            context.remove_all_registrations()


## The module's context, which each file's own is made from, and its id, which
## each file's context's begins with.
var _context: SaContext = null
var _module_id: StringName = &""
## The folder read, the door's for this engine unless a suite names another.
var _folder: String = ""
## Every file read, by its path.
var _entries: Dictionary[String, Entry] = {}


func _init(context: SaContext, module_id: StringName, folder: String = "") -> void:
    _context = context
    _module_id = module_id
    _folder = folder if not folder.is_empty() else SaBrushFieldRegistry.folder_for(NoiseFieldsScript.ENGINE)


## The settings key of number *index* of the field called *field_id*.
static func number_key(field_id: String, index: int) -> StringName:
    return Header.key_for(field_id, index)


## The id a file called *stem* registers its field under.
static func id_for(stem: String) -> String:
    return RegEx.create_from_string("[^a-z0-9_]").sub(stem.to_lower(), "_", true)


## Reads the folder and registers, replaces or drops a field for every file
## whose text moved since the last read, and answers whether any did.
func reread() -> bool:
    var found: Dictionary[String, bool] = {}
    var moved := false
    if DirAccess.dir_exists_absolute(_folder):
        for file_name in DirAccess.get_files_at(_folder):
            if file_name.get_extension() != "gmacs":
                continue
            var path := _folder.path_join(file_name)
            found[path] = true
            if _read(path):
                moved = true
    for path: String in _entries.keys():
        if not found.has(path):
            _entries[path].drop()
            _entries.erase(path)
            moved = true
    return moved


## Drops every field the folder registered, the module's unload.
func forget() -> void:
    for path: String in _entries:
        _entries[path].drop()
    _entries.clear()


## The ids of the fields the folder holds now, in the order they were read.
func ids() -> Array[String]:
    var out: Array[String] = []
    for path: String in _entries:
        if _entries[path].context != null:
            out.append(id_for(path.get_file().get_basename()))
    return out


## Reads the file at *path*, and when its text moved drops its old field and
## registers the new one. Answers whether it moved.
func _read(path: String) -> bool:
    var text := FileAccess.get_file_as_string(path)
    var digest := text.md5_text()
    var held: Entry = _entries.get(path)
    if held != null and held.digest == digest:
        return false
    if held != null:
        held.drop()
    var stem := path.get_file().get_basename()
    var field_id := id_for(stem)
    var context := _context.for_module(StringName("%s/%s" % [_module_id, stem]))
    var header := Header.new(text, field_id, stem)
    var field := SaBrushFieldRegistry.Field.new(
        field_id,
        header.label,
        NoiseFieldsScript.ENGINE,
        SaBrushFieldRegistry.OWN,
        2,
        header.keys,
        header.specs,
        header.defaults,
        path
    )
    var registry := _context.brush_fields
    var taken_by: SaBrushFieldRegistry.Field = registry.field(NoiseFieldsScript.ENGINE, field_id)
    if taken_by != null:
        _pass_over(path, field_id, registry.owner_of(taken_by))
        _entries[path] = Entry.new(digest, null)
        return true
    # The door compiles the function and says why it refuses, and the pass is
    # built from it on the engine's first question, which drops a field whose
    # pass does not build as one that does not compile.
    if not context.register_brush_field(field) or not NoiseFieldsScript.is_ours(field):
        context.remove_all_registrations()
        context = null
    _entries[path] = Entry.new(digest, context)
    return true


## Says through `SaProblems` that *path* is passed over, because the field it
## would be, *field_id*, is *owner*'s already.
static func _pass_over(path: String, field_id: String, owner: StringName) -> void:
    SaProblems.report(
        "NoiseFieldFolder",
        (
            TranslationServer.translate("The noise brush passes over %s, because the brush field '%s' is %s's already.")
            % [path, field_id, String(owner) if not String(owner).is_empty() else "Sara"]
        )
    )
