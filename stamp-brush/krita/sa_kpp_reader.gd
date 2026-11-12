## Reads a Krita brush preset, a `.kpp`, a folder of them or a `.bundle`, to
## one dictionary per preset.
##
## **Written from the file formats, not from Krita's code.** A `.kpp` is a PNG
## whose text chunk `preset` carries the preset as XML, a `.bundle` is a zip of
## the same under `paintoppresets/` with a manifest and a `meta.xml` beside
## them, and both are documented containers. What this file does is walk a PNG's
## chunks, inflate the ones that are deflated, hand the XML to the engine's own
## `XMLParser` and hand the tip bytes the XML embeds to the tip loader's
## from-bytes door. Nothing here decides what a Krita option means in Sara,
## which is the mapping table's work: the option tree comes back as the XML
## gives it, name to type and value, so the table is written against a
## dictionary rather than against a parser.
##
## **The text chunk is compressed more often than not.** The PNG writer Krita
## goes through deflates a text longer than forty bytes and stores it as `zTXt`
## when it is Latin-1 and as `iTXt` when it is not, so a preset carries its XML
## one of those two ways and all but never as the plain `tEXt` the tip loader
## reads for `brush_spacing`. All three are read here, and the deflated ones go
## through the engine's own inflate, which speaks the zlib stream a PNG stores.
##
## **A tip is embedded since Krita 5, and looked up three ways.** The preset's
## `brush_definition` names its tip by `filename` and `md5sum`, and the
## `<resources>` element under the preset carries every resource the preset
## needs, base64 in a CDATA, with the same two keys and a `name`. The tip is the
## resource whose md5sum matches, else whose filename matches, else whose name
## does, and a bundle written before the embedding is looked at last: its tip
## is a file under `brushes/` in the zip. What is found goes through
## [method SaTipImage.load_bytes], which is the door that refuses a `.gih` by
## its name, so the refusal a preset carries is the loader's own sentence.
##
## **Nothing here touches the canvas or the GPU.** Reading a preset is CPU work
## over a file, done once, outside any stroke, and the dictionary is all it
## leaves behind.
class_name SaKppReader
extends RefCounted

## The tip resource `SHAPES` answers in.
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Krita's `MaskGenerator` `id` onto the dab kernel's generator, and its `type`
## onto the tip's shape. Here rather than in the mapping table, because the
## element they read is the one [method tip_of] turns into a dictionary, and
## because two mapping files, `sa_kpp_import.gd` and `sa_kpp_masking.gd`, need
## the same two tables.
const GENERATORS: Dictionary = {"default": 0, "gauss": 1, "softbrush": 2}
const SHAPES: Dictionary = {"circle": SaBrushTipScript.Shape.CIRCLE, "rect": SaBrushTipScript.Shape.RECTANGLE}

## The text chunk key a `.kpp` keeps its XML under, and the one beside it.
const PRESET_KEY: String = "preset"
const VERSION_KEY: String = "version"

## The bundle's own three files and the folder its presets sit in.
const BUNDLE_MIMETYPE_ENTRY: String = "mimetype"
const BUNDLE_MANIFEST_ENTRY: String = "META-INF/manifest.xml"
const BUNDLE_META_ENTRY: String = "meta.xml"
const BUNDLE_PRESETS_DIR: String = "paintoppresets/"
const BUNDLE_BRUSHES_DIR: String = "brushes/"

## The preset param that carries the tip, and the resource type a tip has.
const BRUSH_DEFINITION: String = "brush_definition"
const BRUSHES_TYPE: String = "brushes"

## The tip kinds a preset's dictionary can name. `generated` is Krita's
## `auto_brush`, a circle or a rectangle from a few numbers, `image` is a PNG or
## a GBR whose bytes are in the dictionary, `refused` is a tip the loader named
## and would not read, and `none` is a preset with no brush definition at all.
const TIP_GENERATED: String = "generated"
const TIP_IMAGE: String = "image"
const TIP_REFUSED: String = "refused"
const TIP_NONE: String = "none"

## How Krita applies a tip's picture, the `brushApplication` attribute of the
## `Brush` element, Krita's `enumBrushApplication` written as its number. A
## preset from before the attribute carries `ColorAsMask` alone and reads as
## [constant APPLICATION_UNSTATED]. [constant APPLICATION_GRADIENT_MAP] lands
## on the stamp brush's Gradient Map mode in `sa_kpp_import.gd`.
const APPLICATION_UNSTATED: String = ""
const APPLICATION_ALPHA_MASK: String = "alpha mask"
const APPLICATION_IMAGE_STAMP: String = "image stamp"
const APPLICATION_LIGHTNESS_MAP: String = "lightness map"
const APPLICATION_GRADIENT_MAP: String = "gradient map"
const APPLICATIONS: Dictionary = {
    0: APPLICATION_ALPHA_MASK,
    1: APPLICATION_IMAGE_STAMP,
    2: APPLICATION_LIGHTNESS_MAP,
    3: APPLICATION_GRADIENT_MAP,
}

## How many entry names a refusal over a bundle lists before it counts the
## rest, so a bundle of two hundred files still refuses in one line.
const NAMES_IN_REFUSAL: int = 6

## The largest inflated text chunk believed. A colour smudge preset with a
## photographic pattern embedded base64 is a sixteen megabyte file that opens to
## forty megabytes of XML, so any cap a reader would guess from the file's own
## size is far too low. The cap is there so a file lying about its length cannot
## ask for the whole of memory, not to say how large a preset may be, so it errs
## high, and the refusal names it.
const MAX_INFLATED_BYTES: int = 512 << 20


## The one door for a path: a `.kpp` reads to one preset, a `.bundle` to every
## preset it holds, and a folder to every `.kpp` and `.bundle` directly in it,
## in name order. Anything else answers one dictionary carrying an `error`.
static func read_path(path: String) -> Array[Dictionary]:
    var lower := path.to_lower()
    if DirAccess.dir_exists_absolute(path):
        return _read_folder(path)
    if lower.ends_with(".kpp"):
        return [read_file(path)]
    if lower.ends_with(".bundle"):
        return read_bundle(path)
    return [
        _refused(
            path,
            (
                TranslationServer.translate("%s is not a Krita preset Sara reads. Open a .kpp, a .bundle or a folder of them.")
                % path.get_file()
            )
        )
    ]


## One `.kpp` at *path*.
static func read_file(path: String) -> Dictionary:
    var bytes := FileAccess.get_file_as_bytes(path)
    if bytes.is_empty():
        return _refused(path, TranslationServer.translate("%s could not be read.") % path.get_file())
    var preset := read_bytes(bytes, path)
    var tip: Dictionary = preset["tip"]
    if tip["kind"] == TIP_REFUSED and (tip["bytes"] as PackedByteArray).is_empty():
        _tip_from_sibling_folder(path, preset)
    return preset


## One `.kpp` already in memory, *source* being where it came from, which is
## the path or the bundle entry every message and the `source` key quote.
static func read_bytes(bytes: PackedByteArray, source: String) -> Dictionary:
    var text := png_text_chunks(bytes)
    if text.is_empty() and not _is_png(bytes):
        return _refused(source, TranslationServer.translate("%s is not a PNG, and a .kpp is one.") % source.get_file())
    if not text.has(PRESET_KEY):
        return _refused(
            source,
            (
                TranslationServer.translate("%s carries no preset text chunk, so it is a picture rather than a Krita preset.")
                % source.get_file()
            )
        )
    if String(text[PRESET_KEY]).is_empty():
        return _refused(
            source,
            (
                TranslationServer.translate("%s carries a preset text chunk that inflates to nothing, or to more than %s MB.")
                % [source.get_file(), MAX_INFLATED_BYTES >> 20]
            )
        )
    var preset := parse_preset_xml(String(text[PRESET_KEY]), source)
    preset["format_version"] = String(text.get(VERSION_KEY, ""))
    return preset


## A `.bundle`, which is a zip: every `.kpp` under `paintoppresets/`, each
## with the tags the manifest gives its entry and the licence `meta.xml`
## states, in the order the zip lists them.
static func read_bundle(path: String) -> Array[Dictionary]:
    var zip := ZIPReader.new()
    if zip.open(path) != OK:
        return [_refused(path, TranslationServer.translate("%s is not a zip, and a .bundle is one.") % path.get_file())]
    var entries := zip.get_files()
    var meta := _bundle_meta(zip, entries)
    var tags_by_entry := _bundle_tags(zip, entries)
    var out: Array[Dictionary] = []
    for entry in entries:
        if not entry.begins_with(BUNDLE_PRESETS_DIR) or not entry.to_lower().ends_with(".kpp"):
            continue
        var source := "%s/%s" % [path, entry]
        var preset := read_bytes(zip.read_file(entry), source)
        preset["tags"] = tags_by_entry.get(entry, PackedStringArray())
        preset["licence"] = String(meta.get("licence", ""))
        preset["bundle"] = meta
        var tip: Dictionary = preset["tip"]
        if tip.get("kind", "") == TIP_REFUSED and tip.get("bytes", PackedByteArray()).is_empty():
            _tip_from_bundle(zip, entries, preset)
        out.append(preset)
    if out.is_empty():
        out.append(_bundle_without_presets(zip, entries, path))
    zip.close()
    return out


## A bundle that holds no `.kpp` under `paintoppresets/`. A Krita bundle of
## brush tips and nothing else is a normal export, so the `brushes/` folder is
## read and every tip in it comes back under `tips` for the importer to write
## into the painter's tip folder. With neither the answer is the refusal, which
## names both folders and what the zip held instead.
static func _bundle_without_presets(zip: ZIPReader, entries: PackedStringArray, path: String) -> Dictionary:
    var brushes := _bundle_brushes(zip, entries)
    var tips: Array[Dictionary] = brushes["tips"]
    if tips.is_empty():
        return _refused(path, _nothing_in_bundle(path, entries))
    var found := _blank(path)
    found["tips"] = tips
    found["tips_skipped"] = brushes["skipped"]
    return found


## Every entry under `brushes/`, split by the tip loader into the ones it
## reads, each `{"file_name", "bytes"}`, and the file names it will not, which
## are the `.gih` and `.abr` collections a Krita bundle carries beside single
## tips. The door decides rather than an extension list here, so a tip Sara
## cannot read is never written into the tip folder for the chooser to fail on.
static func _bundle_brushes(zip: ZIPReader, entries: PackedStringArray) -> Dictionary:
    var tips: Array[Dictionary] = []
    var skipped := PackedStringArray()
    for entry in entries:
        if not entry.begins_with(BUNDLE_BRUSHES_DIR) or entry.ends_with("/"):
            continue
        var file_name := entry.get_file()
        var bytes := zip.read_file(entry)
        if SaTipImage.load_bytes(bytes, file_name).ok():
            tips.append({"file_name": file_name, "bytes": bytes})
        else:
            skipped.append(file_name)
    return {"tips": tips, "skipped": skipped}


## The refusal for a bundle holding neither a preset nor a tip: both folders
## looked in, by name, and what the zip did hold besides its own three
## housekeeping files, so the sentence says what the bundle is instead of only
## what it is not.
static func _nothing_in_bundle(path: String, entries: PackedStringArray) -> String:
    var names := PackedStringArray()
    for entry in entries:
        var housekeeping := entry in [BUNDLE_MIMETYPE_ENTRY, BUNDLE_MANIFEST_ENTRY, BUNDLE_META_ENTRY]
        if not entry.ends_with("/") and not housekeeping:
            names.append(entry)
    var held := TranslationServer.translate("nothing besides its manifest, its meta.xml and its mimetype")
    if not names.is_empty():
        held = (
            TranslationServer.translate_plural("%d other entry: %s", "%d other entries: %s", names.size())
            % [names.size(), ", ".join(_first_few(names))]
        )
    return (
        TranslationServer.translate("%s holds no preset under %s and no brush tip under %s. It holds %s.")
        % [path.get_file(), BUNDLE_PRESETS_DIR, BUNDLE_BRUSHES_DIR, held]
    )


## At most [constant NAMES_IN_REFUSAL] of *names*, with a count standing for
## the rest.
static func _first_few(names: PackedStringArray) -> PackedStringArray:
    if names.size() <= NAMES_IN_REFUSAL:
        return names
    var few := names.slice(0, NAMES_IN_REFUSAL)
    few.append(
        (
            TranslationServer.translate_plural("and %d more", "and %d more", names.size() - NAMES_IN_REFUSAL)
            % (names.size() - NAMES_IN_REFUSAL)
        )
    )
    return few


## The preset XML to the dictionary. Public so a test can feed it text, and so
## a caller holding the XML from somewhere other than a PNG has a door.
##
## The keys, every one always present:
## `name`, `engine` (Krita's `paintopid`), `version` (the `Preset` element's,
## empty when it has none), `options` (param name to `{"type": ..., "value":
## ...}`, the value as the XML gives it, CDATA unwrapped), `resources` (every
## embedded resource, name to `{"name", "filename", "md5sum", "type",
## "bytes"}`), `tip` (see [method tip_of]), `tags`, `licence`, `bundle`,
## `tips` and `tips_skipped` (both empty unless the source was a bundle that
## held brush tips and no preset at all), `source`, `format_version` and
## `error`, the last empty when the preset read.
static func parse_preset_xml(xml: String, source: String) -> Dictionary:
    var preset := _blank(source)
    var parser := XMLParser.new()
    if parser.open_buffer(xml.to_utf8_buffer()) != OK:
        preset["error"] = TranslationServer.translate("%s carries a preset chunk the XML parser cannot open.") % source.get_file()
        return preset
    var options: Dictionary = preset["options"]
    var resources: Dictionary = preset["resources"]
    var saw_preset := false
    while parser.read() == OK:
        if parser.get_node_type() != XMLParser.NODE_ELEMENT:
            continue
        match parser.get_node_name():
            "Preset":
                saw_preset = true
                preset["name"] = parser.get_named_attribute_value_safe("name")
                preset["engine"] = parser.get_named_attribute_value_safe("paintopid")
                preset["version"] = parser.get_named_attribute_value_safe("version")
            "param":
                var name := parser.get_named_attribute_value_safe("name")
                var kind := parser.get_named_attribute_value_safe("type")
                options[name] = {"type": kind, "value": _element_text(parser)}
            "resource":
                var resource := {
                    "name": parser.get_named_attribute_value_safe("name"),
                    "filename": parser.get_named_attribute_value_safe("filename"),
                    "md5sum": parser.get_named_attribute_value_safe("md5sum"),
                    "type": parser.get_named_attribute_value_safe("type"),
                }
                var encoded := _element_text(parser)
                resource["bytes"] = (
                    Marshalls.base64_to_raw(_strip_whitespace(encoded)) if not encoded.is_empty() else PackedByteArray()
                )
                resources[String(resource["name"])] = resource
    if not saw_preset:
        preset["error"] = (
            TranslationServer.translate("%s carries a preset chunk with no Preset element in it.") % source.get_file()
        )
        return preset
    preset["tip"] = tip_of(preset)
    return preset


## Every text chunk of a PNG, key to text: `tEXt` as it stands, `zTXt`
## inflated, and `iTXt` inflated when its flag says so. Empty for bytes that
## are not a PNG.
##
## By hand, because `Image` discards every ancillary chunk. The layout is the
## one every PNG has: eight bytes of signature, then per chunk a big-endian
## length, a four-letter type, the data and a CRC that is not checked here,
## because a chunk that inflates and parses is its own check and one that does
## not is refused a step later with a better sentence.
static func png_text_chunks(bytes: PackedByteArray) -> Dictionary:
    var out: Dictionary = {}
    if not _is_png(bytes):
        return out
    var at := 8
    while at + 8 <= bytes.size():
        var length := _be_u32(bytes, at)
        var kind := bytes.slice(at + 4, at + 8).get_string_from_ascii()
        var data_at := at + 8
        if length < 0 or data_at + length > bytes.size():
            break
        if kind == "tEXt" or kind == "zTXt" or kind == "iTXt":
            var raw := bytes.slice(data_at, data_at + length)
            var split := raw.find(0)
            if split > 0:
                var key := raw.slice(0, split).get_string_from_ascii()
                out[key] = _text_chunk_body(kind, raw.slice(split + 1))
        if kind == "IEND":
            break
        at = data_at + length + 4
    return out


## The text after a chunk's key, by the chunk's kind. `tEXt` is Latin-1 as it
## stands. `zTXt` is one byte of compression method and then a zlib stream of
## Latin-1. `iTXt` is a compression flag, a compression method, a language tag
## and a translated keyword, each of the last two terminated, and then UTF-8,
## deflated when the flag is one.
static func _text_chunk_body(kind: String, body: PackedByteArray) -> String:
    match kind:
        "tEXt":
            return body.get_string_from_ascii()
        "zTXt":
            if body.size() < 2:
                return ""
            return _inflate(body.slice(1)).get_string_from_ascii()
        "iTXt":
            if body.size() < 4:
                return ""
            var compressed := body[0] == 1
            var rest := body.slice(2)
            var language_end := rest.find(0)
            if language_end < 0:
                return ""
            rest = rest.slice(language_end + 1)
            var keyword_end := rest.find(0)
            if keyword_end < 0:
                return ""
            rest = rest.slice(keyword_end + 1)
            if compressed:
                rest = _inflate(rest)
            return rest.get_string_from_utf8()
    return ""


## A zlib stream inflated through the engine. `COMPRESSION_DEFLATE` is the
## engine's name for zlib with its two-byte header, which is what a PNG stores.
static func _inflate(stream: PackedByteArray) -> PackedByteArray:
    return stream.decompress_dynamic(MAX_INFLATED_BYTES, FileAccess.COMPRESSION_DEFLATE)


static func _is_png(bytes: PackedByteArray) -> bool:
    return bytes.size() > 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47


static func _be_u32(bytes: PackedByteArray, at: int) -> int:
    if at + 4 > bytes.size():
        return 0
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## The text and CDATA between an element's start and its end, joined. Leaves
## the parser on the end tag, so the loop above sees the next element next.
##
## A CDATA section's content comes back from `get_node_name`, not from
## `get_node_data`, which errors on anything but a text node: the parser keeps
## one string per node and files a CDATA's under the name. Found by probing,
## and the reason every option of the first fixture read as empty.
static func _element_text(parser: XMLParser) -> String:
    if parser.is_empty():
        return ""
    var name := parser.get_node_name()
    var text := ""
    while parser.read() == OK:
        var node_type := parser.get_node_type()
        if node_type == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == name:
            break
        if node_type == XMLParser.NODE_TEXT:
            text += parser.get_node_data()
        elif node_type == XMLParser.NODE_CDATA:
            text += parser.get_node_name()
    return text


static func _strip_whitespace(text: String) -> String:
    return text.replace("\n", "").replace("\r", "").replace(" ", "").replace("\t", "")


## One attribute of a `Brush` or `MaskGenerator` element, as the XML wrote it,
## `fallback` when the attribute is absent or is not a number. The tip
## dictionaries this file builds carry their attributes as strings, which is
## what the element said, and this is the door the mapping tables read them
## through.
static func attr_float(attributes: Dictionary, key: String, fallback: float) -> float:
    var text := String(attributes.get(key, "")).strip_edges()
    return float(text) if text.is_valid_float() else fallback


## The tip of a parsed preset, from its `brush_definition` option.
##
## `kind` is one of the four `TIP_` constants. `format` is `png` or `gbr` for an
## image, `generator` is the `MaskGenerator` element's attributes for a
## generated tip, `brush` is the `Brush` element's own attributes for either,
## spacing, angle, scale and the rest, `file_name` and `bytes` are the embedded
## resource's, `size` is what the tip loader made of the bytes, and `error` is
## the loader's sentence when it refused, or this file's when nothing was
## embedded to hand it.
static func tip_of(preset: Dictionary) -> Dictionary:
    var tip := _blank_tip()
    var options: Dictionary = preset["options"]
    if not options.has(BRUSH_DEFINITION):
        return tip
    var definition := String(options[BRUSH_DEFINITION]["value"])
    var parser := XMLParser.new()
    if parser.open_buffer(definition.to_utf8_buffer()) != OK:
        tip["kind"] = TIP_REFUSED
        tip["error"] = (
            TranslationServer.translate("%s carries a brush definition the XML parser cannot open.")
            % String(preset["source"]).get_file()
        )
        return tip
    while parser.read() == OK:
        if parser.get_node_type() != XMLParser.NODE_ELEMENT:
            continue
        match parser.get_node_name():
            "Brush":
                tip["brush"] = _attributes(parser)
            "MaskGenerator":
                tip["generator"] = _attributes(parser)
    var brush: Dictionary = tip["brush"]
    tip["application"] = application_of(brush)
    var brush_type := String(brush.get("type", ""))
    if brush_type == "auto_brush":
        tip["kind"] = TIP_GENERATED
        return tip
    tip["file_name"] = String(brush.get("filename", ""))
    var resource := _find_tip_resource(preset["resources"], brush)
    if resource.is_empty():
        tip["kind"] = TIP_REFUSED
        tip["error"] = _not_embedded(preset, brush_type, tip["file_name"])
        return tip
    var tip_file := String(tip["file_name"]) if not String(tip["file_name"]).is_empty() else String(resource["filename"])
    _tip_from_bytes(tip, resource["bytes"], tip_file)
    return tip


## The mode a `Brush` element's attributes put the tip's picture in, one of the
## `APPLICATION_` names, or [constant APPLICATION_UNSTATED] when the attribute
## is missing or not a number Krita writes.
static func application_of(brush: Dictionary) -> String:
    var text := String(brush.get("brushApplication", "")).strip_edges()
    if not text.is_valid_int():
        return APPLICATION_UNSTATED
    return String(APPLICATIONS.get(text.to_int(), APPLICATION_UNSTATED))


## What the loader makes of a tip's bytes, written into *tip*: the door is the
## one that decides the format by the name. A `.gih` goes to the pipe reader
## rather than the single-tip door, which still refuses a collection by name.
static func _tip_from_bytes(tip: Dictionary, bytes: PackedByteArray, file_name: String) -> void:
    tip["file_name"] = file_name
    tip["bytes"] = bytes
    var lower := file_name.to_lower()
    tip["format"] = "png" if lower.ends_with(".png") else "gbr" if lower.ends_with(".gbr") else lower.get_extension()
    if lower.ends_with(".gih"):
        _pipe_from_bytes(tip, bytes, file_name)
        return
    var loaded := SaTipImage.load_bytes(bytes, file_name)
    if loaded.ok():
        tip["kind"] = TIP_IMAGE
        tip["size"] = loaded.size
        tip["spacing"] = loaded.spacing
    else:
        tip["kind"] = TIP_REFUSED
        tip["error"] = loaded.error


## A `.gih` through the pipe reader rather than the single-tip door. A pipe Sara
## reads becomes an image tip whose file is written to the tips folder and
## loaded the way a `.gbr` is, its selection modes carried by the file itself. A
## pipe with a selection mode outside Sara's eight is refused, and
## [member selection] names the mode so the import can tag the preset with it
## rather than with the whole tip.
static func _pipe_from_bytes(tip: Dictionary, bytes: PackedByteArray, file_name: String) -> void:
    var pipe := SaGihPipe.read_bytes(bytes, file_name)
    if pipe.ok():
        tip["kind"] = TIP_IMAGE
        tip["size"] = pipe.tips[0].size
        tip["spacing"] = pipe.tips[0].spacing
        return
    tip["kind"] = TIP_REFUSED
    tip["error"] = pipe.error
    var unknown := SaGihPipe.unknown_selection(bytes)
    if not unknown.is_empty():
        tip["selection"] = unknown


## The sentence for a tip the preset names and does not carry. An `.abr` gets
## the loader's own refusal even here, so a painter reads one message for the
## format whether or not the bytes came along.
##
## **A `.gih` is told it is missing**, because Sara reads a pipe now and the
## loader's sentence, that a collection is not read yet, would blame a format
## for a file that never arrived. Krita 5 keeps its pipes in bundles and a
## resource cache rather than a `brushes/` folder, so a preset exported from
## its `paintoppresets/` folder without its tip is the common case, and the
## sentence says where the reader looked.
static func _not_embedded(preset: Dictionary, brush_type: String, file_name: String) -> String:
    if file_name.to_lower().ends_with(".gih"):
        return (
            TranslationServer.translate("%s names the pipe %s, does not embed it, and no brushes folder beside it holds it.")
            % [String(preset["source"]).get_file(), file_name]
        )
    if file_name.to_lower().ends_with(".abr"):
        return SaTipImage.load_bytes(PackedByteArray(), file_name).error
    if file_name.is_empty():
        return TranslationServer.translate("%s names a %s with no file name.") % [String(preset["source"]).get_file(), brush_type]
    return (
        TranslationServer.translate("%s names the tip %s and does not embed it.")
        % [String(preset["source"]).get_file(), file_name]
    )


## The embedded resource a brush definition points at: by md5sum, then by
## file name, then by name, among the resources of the brushes type. The
## md5sum is the key Krita matches on itself, and the two names are the
## fallbacks for a file whose md5sum field was left empty by hand.
static func _find_tip_resource(resources: Dictionary, brush: Dictionary) -> Dictionary:
    var wanted_sum := String(brush.get("md5sum", ""))
    var wanted_file := String(brush.get("filename", ""))
    var wanted_name := wanted_file.get_basename()
    for pass_index in 3:
        for key: Variant in resources:
            var resource: Dictionary = resources[key]
            if String(resource["type"]) != BRUSHES_TYPE:
                continue
            var hit := false
            match pass_index:
                0:
                    hit = not wanted_sum.is_empty() and String(resource["md5sum"]) == wanted_sum
                1:
                    hit = not wanted_file.is_empty() and String(resource["filename"]) == wanted_file
                2:
                    hit = not wanted_name.is_empty() and String(resource["name"]) == wanted_name
            if hit:
                return resource
    return {}


## A bundle written before Krita embedded tips keeps them as files under
## `brushes/`, so a preset whose tip was not embedded looks there, by the file
## name the brush definition gives.
static func _tip_from_bundle(zip: ZIPReader, entries: PackedStringArray, preset: Dictionary) -> void:
    var tip: Dictionary = preset["tip"]
    var file_name := String(tip.get("file_name", ""))
    if file_name.is_empty():
        return
    var entry := BUNDLE_BRUSHES_DIR + file_name
    if not entries.has(entry):
        return
    tip["error"] = ""
    _tip_from_bytes(tip, zip.read_file(entry), file_name)


## A preset saved before Krita embedded tips names a file that lives in the
## `brushes/` folder beside the `paintoppresets/` one, which is how a Krita
## resource folder is laid out, so a `.kpp` read from such a folder looks there.
## Without this such a preset comes across with no tip and a message about a
## file that is one directory away.
static func _tip_from_sibling_folder(path: String, preset: Dictionary) -> void:
    var tip: Dictionary = preset["tip"]
    var file_name := String(tip.get("file_name", ""))
    if file_name.is_empty():
        return
    var sibling := path.get_base_dir().get_base_dir().path_join(BUNDLE_BRUSHES_DIR + file_name)
    if not FileAccess.file_exists(sibling):
        return
    var bytes := FileAccess.get_file_as_bytes(sibling)
    if bytes.is_empty():
        return
    tip["error"] = ""
    _tip_from_bytes(tip, bytes, file_name)


## The manifest's tags per entry, `manifest:full-path` to the `manifest:tag`
## texts under it.
static func _bundle_tags(zip: ZIPReader, entries: PackedStringArray) -> Dictionary:
    var out: Dictionary = {}
    if not entries.has(BUNDLE_MANIFEST_ENTRY):
        return out
    var parser := XMLParser.new()
    if parser.open_buffer(zip.read_file(BUNDLE_MANIFEST_ENTRY)) != OK:
        return out
    var current := ""
    while parser.read() == OK:
        if parser.get_node_type() != XMLParser.NODE_ELEMENT:
            continue
        match parser.get_node_name():
            "manifest:file-entry":
                current = parser.get_named_attribute_value_safe("manifest:full-path")
                out[current] = PackedStringArray()
            "manifest:tag":
                if not current.is_empty():
                    var tags: PackedStringArray = out[current]
                    tags.append(_element_text(parser).strip_edges())
                    out[current] = tags
    return out


## `meta.xml`, the elements a bundle states about itself: `licence`, `author`,
## `title`, `description`, `website`, `generator` and `date`, each empty when
## the file does not say. The licence is read from `meta:license` and, when
## that is missing, from the `meta:meta-userdefined` row named `license`, the
## two places the format has kept it.
static func _bundle_meta(zip: ZIPReader, entries: PackedStringArray) -> Dictionary:
    var out := {"licence": "", "author": "", "title": "", "description": "", "website": "", "generator": "", "date": ""}
    if not entries.has(BUNDLE_META_ENTRY):
        return out
    var parser := XMLParser.new()
    if parser.open_buffer(zip.read_file(BUNDLE_META_ENTRY)) != OK:
        return out
    var by_element := {
        "meta:license": "licence",
        "dc:author": "author",
        "dc:title": "title",
        "dc:description": "description",
        "meta:website": "website",
        "meta:generator": "generator",
        "meta:dc-date": "date",
    }
    while parser.read() == OK:
        if parser.get_node_type() != XMLParser.NODE_ELEMENT:
            continue
        var element := parser.get_node_name()
        if by_element.has(element):
            out[by_element[element]] = _element_text(parser).strip_edges()
        elif element == "meta:meta-userdefined":
            var name := parser.get_named_attribute_value_safe("meta:name")
            var value := parser.get_named_attribute_value_safe("meta:value")
            var key := "licence" if name == "license" else name
            if out.has(key) and String(out[key]).is_empty():
                out[key] = value
    return out


## Every `.kpp` and `.bundle` directly in *path*, in name order, so two runs
## over one folder answer the same list in the same order.
static func _read_folder(path: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var dir := DirAccess.open(path)
    if dir == null:
        return [_refused(path, TranslationServer.translate("%s could not be opened as a folder.") % path)]
    var names := dir.get_files()
    names.sort()
    for name in names:
        var lower := name.to_lower()
        if lower.ends_with(".kpp") or lower.ends_with(".bundle"):
            out.append_array(read_path(path.path_join(name)))
    if out.is_empty():
        out.append(_refused(path, TranslationServer.translate("%s holds no .kpp and no .bundle.") % path))
    return out


static func _attributes(parser: XMLParser) -> Dictionary:
    var out: Dictionary = {}
    for i in parser.get_attribute_count():
        out[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
    return out


static func _blank(source: String) -> Dictionary:
    return {
        "name": "",
        "engine": "",
        "version": "",
        "format_version": "",
        "options": {},
        "resources": {},
        "tip": _blank_tip(),
        "tags": PackedStringArray(),
        "licence": "",
        "bundle": {},
        "tips": [],
        "tips_skipped": PackedStringArray(),
        "source": source,
        "error": "",
    }


static func _blank_tip() -> Dictionary:
    return {
        "kind": TIP_NONE,
        "format": "",
        "file_name": "",
        "bytes": PackedByteArray(),
        "size": Vector2i.ZERO,
        "spacing": 0.0,
        "brush": {},
        "application": APPLICATION_UNSTATED,
        "generator": {},
        "error": "",
        "selection": "",
    }


static func _refused(source: String, reason: String) -> Dictionary:
    var preset := _blank(source)
    preset["error"] = reason
    return preset
