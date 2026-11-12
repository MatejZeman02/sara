## What a scenario does to the open document, each step starting where a dialog
## or a popup hands off.
##
## Every one of these exists for the same reason and says so in its own comment:
## the control that would reach it lives in an embedded `Window` or a
## `MenuButton` popup, and an injected click does not route into one. So a `New`
## starts after the New Document dialog would have been confirmed, an `Open`
## after the file chooser, a preset after the list has been popped. What is
## being proved is what the app does with the answer, never the dialog.
##
## [method history] is the odd one and is here for the same shape rather than
## the same reason: undo and redo go straight at the document's `UndoRedo`,
## because whether the shortcut is bound is a separate question from whether the
## history is right.
##
## Reached by path from the runner rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaScenarioDocument
extends RefCounted

## The canvas driver, for the one lookup this shares with it.
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const MenuDriver := preload("res://harness/drivers/menu/sa_menu_driver.gd")
## What refuses a `size` side no dialog could have made.
const SizeCheck := preload("res://harness/scenario/sa_scenario_size.gd")

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The run, read for its tree and its folder, and written with what the last
## `save` came to.
var _run: CaptureRun = null
## Whether the open over frames under way made the canvas its size as its
## stack landed, so its end need not make it again, as File > Open skips it.
var _sized_at_landing := false

## How many saves over frames are still being written, which holds the door's
## answer to a `save`, [method still_saving]. Static, because the door asks it
## of the class as it asks [method still_loading].
static var _saves_on_their_way := 0
## How many exports over frames are still being written, which holds the
## door's answer to an `export` as [member _saves_on_their_way] holds a save's.
static var _exports_on_their_way := 0


func _init(run: CaptureRun) -> void:
    _run = run


## The document the main canvas is showing, or null before one exists. Through
## the canvas driver's lookup rather than the run's, because that one also wants
## the canvas to hold a document, which every step here does too.
func _document() -> SaDocument:
    var canvas := CanvasDriver.main_canvas()
    return canvas.document if canvas != null else null


## Saves the main document: the way File > Save As does once its dialog has been
## confirmed, so the document is marked as that file, and how long the save took
## is printed, which is the number the autosave's stall is measured by, one
## autosave being one Save, `{"save": "user://measure.sad"}`, and in JPEG XL
## through the codec File > Save as JPEG XL asks for,
## `{"save": {"path": "user://measure.sad", "codec": "jxl"}}`.
##
## **Arguments.**
## - `save` string or object, a `.sad` path, or its `path`, `codec` and
##   `over_frames`.
##
## It goes as far as the menu item does rather than stopping at `SaExport`, one
## call short of it, where a scenario that saved would read `modified` true and
## an empty `path` afterwards and could prove nothing about what a save does to
## a document. The recent files list is the menu's own and is not touched here: a
## scenario writing to `user://` should not push entries into the person's
## Preferences.
##
## A save that fails fills `said` too, the painter's line ending in
## `SaSadFile.why_not_saved`, and `kept`, the side file a failed rename left or
## empty, and the door answers a `save` step with the whole of it.
##
## Here rather than on the runner, because the `last_save` it fills is the
## run's, and a save is a thing done to the document, which is this driver's
## subject.
##
## *what* is the path, or `{"path": ..., "codec": "jxl"}` for a save in a codec
## asked for by its name, which File > Save as JPEG XL is: the same background
## save the menu starts, waited out here so the file is on disk when the step
## ends. A codec no module registers is refused with the menu's own line and
## writes nothing. `last_save` names the codec, `zstd` for the plain form.
##
## With `over_frames` the save is the background save Ctrl+S starts, and the step returns at once while the window
## draws on. `last_save` is filled when the file is whole, which
## [method still_saving] says, and the door waits on it to answer. The door
## saves so unless the step says `"over_frames": false`, [method as_the_door_runs].
func save_document(what: Variant) -> void:
    var spec: Dictionary = what if what is Dictionary else {"path": what}
    var path := String(spec.get("path", ""))
    var codec := StringName(String(spec.get("codec", "")))
    var document := _document()
    if document == null:
        push_warning("SaCapture: no document to save")
        return
    if not codec.is_empty() and SaCodecRegistry.shared().named(codec) == null:
        _refuse_codec(path, codec)
        return
    var started := Time.get_ticks_usec()
    if bool(spec.get("over_frames", false)):
        # Counted before the save starts, since a save that fails at once
        # answers inside the call.
        _saves_on_their_way += 1
        # Taken on the card as Ctrl+S takes it, and not only for the file: a
        # save handed a preview so is the one that sends its hashes and walks
        # its layers in shares over frames, and one handed none takes its whole
        # snapshot in one, 471 ms on a large document.
        var preview := SaExport.take_preview(document.get_parent() as SaEasel)
        var then := _saved_over_frames.bind(path, codec, started)
        SaSadFile.save_in_background(document, path, 0, preview, true, then, true, codec)
        return
    var err: Error = SaExport.save_sad(document, path, 0, null, true) if codec.is_empty() else _save_in(document, path, codec)
    if err == OK and codec.is_empty():
        document.mark_saved(path)
    _note_save(err, path, codec, started)


## What a save over frames does once its file is whole or has failed. The
## background save marked the document saved itself, when nothing changed
## after its snapshot.
func _saved_over_frames(err: Error, path: String, codec: StringName, started: int) -> void:
    _saves_on_their_way = maxi(_saves_on_their_way - 1, 0)
    _note_save(err, path, codec, started)


## Fills `last_save` for the save of *path* begun at *started*, and prints it.
func _note_save(err: Error, path: String, codec: StringName, started: int) -> void:
    var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
    var size := FileAccess.get_file_as_bytes(path).size() if err == OK else 0
    var named := "zstd" if codec.is_empty() else String(codec)
    _run.last_save = {"path": path, "codec": named, "error": error_string(err), "ms": elapsed_ms, "bytes": size}
    if err != OK:
        var kept := path + SaSadFile.SAD_TEMP_SUFFIX
        var why := SaSadFile.why_not_saved(path)
        _run.last_save["said"] = TranslationServer.translate("Could not save '%s' (%s).") % [path, error_string(err)] + why
        _run.last_save["kept"] = ProjectSettings.globalize_path(kept) if FileAccess.file_exists(kept) else ""
    print("SaCapture: save %s -> %s, %.1f ms, %d bytes" % [path, error_string(err), elapsed_ms, size])


## Writes *document* to *path* in *codec* through the background save File >
## Save as JPEG XL starts, with the preview taken on the card as the menu takes
## it, and drives that save to its end before answering. The save marks the
## document as that file itself, as it does for the menu. No older copies are
## kept beside it, as the plain form keeps none.
func _save_in(document: SaDocument, path: String, codec: StringName) -> Error:
    var ended: Array[Error] = [ERR_TIMEOUT]
    var preview := SaExport.take_preview(document.get_parent() as SaEasel)
    SaSadFile.save_in_background(document, path, 0, preview, true, func(err: Error) -> void: ended[0] = err, true, codec)
    SaSadFile.finish_saves()
    return ended[0]


## Fills `last_save` for a save in *codec*, which no module registers, with the
## refusal File > Save as JPEG XL gives in the same case. The step's answer
## carries it, and nothing is written.
func _refuse_codec(path: String, codec: StringName) -> void:
    var said := TranslationServer.translate(
        "Save as JPEG XL needs the JPEG XL module, which this Sara did not load. Nothing was saved."
    )
    _run.last_save = {"path": path, "codec": String(codec), "error": error_string(ERR_UNAVAILABLE), "said": said, "bytes": 0}
    print("SaCapture: save %s refused, no codec called %s" % [path, codec])


## Exports by file extension: the path's own, PNG, JPG, EXR or any format a
## module registers, TIFF and ORA among them, through the format's writer, the
## call the Export dialog makes once its file picker answers,
## `{"export": "user://picture.png"}`. The dialog's own Export button opens a
## native `FileDialog`, which a scenario cannot drive, so this starts one step
## further in, the way `open` does for the dialogs whose menu items a click
## cannot reach.
##
## *options* is the step itself, each key a row of the dialog no injected click
## reaches: `bits`, the depth row, `{"export": "x.tif", "bits": 16}` for the
## sixteen-bit integer TIFF, the format's own default when the format has no
## such depth, and `png_bits`, an older name for it, eight when neither is
## named. `bake_relief`, the relief row, null taking the row's default, on when
## the document shows height. `tonemap`, the rolloff check, off as the dialog
## opens. `stops`, the view's display exposure ahead of that rolloff, so
## `{"export": "night.png", "tonemap": true, "stops": -2}` writes a night scene
## at two stops under, the lights' insides back. It rides on the rolloff and is refused without
## `tonemap`. It is not `exposure_stops`, the Display page's step, which would
## take the step first. `over_frames` writes it as File > Export does, over
## frames for a format that can, and the step returns at once while the window
## draws on. The door exports so unless the step says `"over_frames": false`,
## and holds its answer until `last_export` says how it ended,
## [method still_saving].
func export_file(path: String, options: Dictionary = {}) -> void:
    var canvas := CanvasDriver.main_canvas()
    if canvas == null:
        push_warning("SaCapture: no canvas to export")
        _run.last_export = {"path": path, "error": "there is no canvas to export"}
        return
    var bits := int(options.get("bits", options.get("png_bits", 8)))
    var bake_relief: Variant = options.get("bake_relief", null)
    var relief := SaRelief.shows_height(canvas.document) if bake_relief == null else bool(bake_relief)
    var tonemap := bool(options.get("tonemap", false))
    var exposure_stops := float(options.get("stops", 0.0))
    if exposure_stops != 0.0 and not (tonemap and path.get_extension().to_lower() == "png"):
        push_warning("SaCapture: export %s refused, an exposure is a tonemapped PNG's alone" % path)
        var refused := "stops ride on a tonemapped PNG alone, %s" % error_string(ERR_INVALID_PARAMETER)
        _run.last_export = {"path": path, "error": refused}
        return
    var error := ERR_FILE_UNRECOGNIZED
    var format := SaImageImport.formats().exported_named(path)
    # The painter's gamut mapping, handed on the way the dialog hands it. The facade drops it for the 32-bit TIFF on its own.
    var mapping := SaSettings.gamut_mapping
    if format != null:
        # `bits` is the depth when the format offers it, and any other writes at the format's own default.
        var write := SaImageFormat.Write.new()
        write.depth = bits if format.depth_ids().has(bits) else format.default_depth
        write.rolloff = tonemap and format.clips(write.depth)
        write.mapping = mapping
        write.relief = relief and format.rows.has(SaImageFormat.ROW_RELIEF)
        write.stops = exposure_stops
        if bool(options.get("over_frames", false)):
            _exports_on_their_way += 1
            format.write_picture_in_turns(canvas.easel, path, write, _exported_over_frames.bind(path, bits, mapping, relief))
            return
        error = format.write_picture(canvas.easel, path, write)
    _note_export(error, path, bits, mapping, relief)


## What an export over frames does once its file is whole or has failed.
func _exported_over_frames(error: Error, path: String, bits: int, mapping: String, relief: bool) -> void:
    _exports_on_their_way = maxi(_exports_on_their_way - 1, 0)
    _note_export(error, path, bits, mapping, relief)


## Fills `last_export` for the export of *path* that ended in *error*, and
## prints it.
func _note_export(error: Error, path: String, bits: int, mapping: String, relief: bool) -> void:
    var bytes := FileAccess.get_file_as_bytes(path) if error == OK else PackedByteArray()
    print("SaCapture: export %s -> err %d, %d bytes" % [ProjectSettings.globalize_path(path), error, bytes.size()])
    # The primaries code read back off the file, -1 for none, so a dump says what the file names.
    _run.last_export = {"path": path, "bits": bits, "bytes": bytes.size(), "primaries": SaExportGamut.png_primaries_at(path)}
    # A write that failed, a folder that is not there above all, says so here,
    # and the door answers ok false on it rather than a true no script reads past.
    if error != OK:
        _run.last_export["error"] = "%s was not written (%s)" % [ProjectSettings.globalize_path(path), error_string(error)]
    # The mode the file was written under and its middle texel read back off
    # the file, so a dump shows what the mapping did to the bytes.
    _run.last_export["gamut_mapping"] = mapping
    _run.last_export["bake_relief"] = relief
    # Read back through the registry, so every flat format a reader is registered for says its middle.
    var readable := error == OK and SaImageImport.formats().flat_named(path) != null
    var written := SaImageImport.read(ProjectSettings.globalize_path(path)) if readable else null
    if written != null and not written.is_empty():
        var middle := written.get_pixel(written.get_width() >> 1, written.get_height() >> 1)
        _run.last_export["middle"] = [middle.r8, middle.g8, middle.b8]


## Writes a picture of the canvas: the composite, to *spec*'s `path`, of the
## document region `rect` at `scale` with a labelled `grid` when asked, or else
## scaled so its long edge is `long_edge`, and prints the path it wrote, which
## is the `look` step, `{"look": {"path": "a.png", "rect": [100, 40, 100, 80], "scale": 2, "grid": 50}}`.
##
## **Arguments.**
## - `path` string, a `.png` file, in the run's folder when bare.
## - `long_edge` integer, in pixels, the canvas's own at zero.
## - `rect` array `[x, y, w, h]` in document pixels, the part of the canvas
##   written, cut to the canvas. The whole canvas when absent.
## - `scale` number, output pixels a document pixel, nearest neighbour from one
##   up. It wins over `long_edge`.
## - `grid` integer, a spacing in document pixels: a line at each multiple of it
##   inside the region, labelled with its document coordinate, drawn over the
##   written picture only and never on a layer. None when absent or zero.
##
## The last three spare a client drawing its own grid on an export it
## cropped and scaled to know where things are. The picture's pixel at document point `(x, y)` is at
## `((x - rect.x) * scale, (y - rect.y) * scale)`.
##
## What a companion painting through the door sees. The door answers a state
## dump, which is numbers, and a model asked to keep painting has to be able to
## look at what it painted, so this hands it a file rather than a number.
##
## `SaExport.get_preview_image` and nothing else, which is the readback export
## already makes: the first hard rule allows the canvas to leave VRAM on export,
## and a second path down from the GPU for the same picture would be a second
## thing to keep correct. The resize is on the CPU image afterwards, so the
## canvas is read once whatever size is asked for.
##
## The picture rather than the numbers the document stores, because a default
## document stores Oklab, and `SaExport.get_canvas_image` would hand a companion
## a dark red field for a grey canvas. `get_preview_image` converts through the document's own space into plain
## sRGB, the way a recorded frame does through `SaRecorder.display_image`, and
## the stored-numbers read stays what a PNG named for the document's gamut
## wants. The preview a `.sad` carries has the same trap.
##
## `long_edge` at or below zero means the canvas's own size, and a canvas already
## shorter than the number asked for is written as it is rather than blown up.
##
## A bare `path` lands in the run's own output directory beside the shots, the
## way a `shot` label does, because a picture the run made belongs with the rest
## of the run's proof. A `user://` or an absolute path is taken as written, see
## [method look_path], and a Windows client's `C:\Users\me\look.png` is one:
## asking for a leading slash or a `://` put `user://captures/` in front of a
## drive letter. The line it prints names the path as the machine spells it, so
## a client that reads the line opens the file.
func look(spec: Dictionary) -> void:
    var canvas := CanvasDriver.main_canvas()
    if canvas == null:
        push_warning("SaCapture: no canvas to look at")
        return
    var path := String(spec.get("path", ""))
    if path.is_empty():
        push_warning("SaCapture: look step has no path to write")
        return
    var written := look_path(_run.out_dir, path)
    if written != path:
        DirAccess.make_dir_recursive_absolute(_run.out_dir)
    path = written
    var img := SaExport.get_preview_image(canvas.easel)
    if img == null:
        push_warning("SaCapture: look could not read the canvas back")
        return
    var was := img.get_size()
    var picture := framed(img, spec)
    if picture == null:
        return
    var error := picture.save_png(path)
    var size := picture.get_size()
    var named := ProjectSettings.globalize_path(path)
    print("SaCapture: look %s -> err %d, %dx%d from %dx%d" % [named, error, size.x, size.y, was.x, was.y])


## The picture a `look` writes, made of the canvas's whole picture *img* by
## *spec*'s `rect`, `scale`, `long_edge` and `grid`, or null with a warning when
## a key is malformed or the rect misses the canvas.
##
## The crop and the resize are on the CPU image the readback already made, and
## the grid is drawn into that image, so no layer and no texture is touched.
## Without a `rect`, a `scale` and a `grid` this is the whole picture shrunk to
## `long_edge`.
##
## A `scale` of one or more resizes by nearest neighbour, so one document pixel
## becomes a square of whole output pixels and a coordinate read off the
## picture lands on the pixel it names. Below one it is Lanczos, as `long_edge`
## is. `scale` wins over `long_edge` when both are given.
static func framed(img: Image, spec: Dictionary) -> Image:
    var whole := Rect2i(Vector2i.ZERO, img.get_size())
    var region := whole
    if spec.has("rect"):
        var asked: Variant = spec["rect"]
        if not (asked is Array) or (asked as Array).size() != 4:
            push_warning("SaCapture: look's rect is four numbers [x, y, w, h], not %s" % [asked])
            return null
        var r := asked as Array
        region = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).intersection(whole)
        if region.size.x <= 0 or region.size.y <= 0:
            push_warning("SaCapture: look's rect %s misses the %dx%d canvas" % [asked, whole.size.x, whole.size.y])
            return null
    var out := img if region == whole else img.get_region(region)
    if spec.has("scale"):
        var scale := float(spec["scale"])
        if scale <= 0.0:
            push_warning("SaCapture: look's scale must be above zero, not %s" % [spec["scale"]])
            return null
        var filter := Image.INTERPOLATE_NEAREST if scale >= 1.0 else Image.INTERPOLATE_LANCZOS
        out.resize(maxi(1, roundi(region.size.x * scale)), maxi(1, roundi(region.size.y * scale)), filter)
    else:
        var wanted := int(spec.get("long_edge", 0))
        var longest := maxi(region.size.x, region.size.y)
        if wanted > 0 and longest > wanted:
            var shrink := float(wanted) / float(longest)
            out.resize(
                maxi(1, roundi(region.size.x * shrink)), maxi(1, roundi(region.size.y * shrink)), Image.INTERPOLATE_LANCZOS
            )
    var spacing := int(spec.get("grid", 0))
    if spacing > 0:
        LookGrid.new(out, region, spacing).draw()
    return out


## The grid a `look` draws over the picture it writes: a line at every
## multiple of the spacing in document pixels inside the region, each labelled
## with its document coordinate.
##
## A line's pixel is black over light paint and white over dark, chosen per
## pixel, so it reads on any paint. A label is white figures on a black box,
## which reads the same everywhere. The figures are a 3 by 5 bitmap drawn at
## twice that, because a harness step has no font of its own to reach for and
## a theme's would be a node it does not need.
class LookGrid:
    ## The figures, each five rows of three bits, the top row first.
    const GLYPHS := {
        "0": [7, 5, 5, 5, 7],
        "1": [2, 6, 2, 2, 7],
        "2": [7, 1, 7, 4, 7],
        "3": [7, 1, 7, 1, 7],
        "4": [5, 5, 7, 1, 1],
        "5": [7, 4, 7, 1, 7],
        "6": [7, 4, 7, 5, 7],
        "7": [7, 1, 1, 1, 1],
        "8": [7, 5, 7, 5, 7],
        "9": [7, 5, 7, 1, 7],
        "-": [0, 0, 7, 0, 0],
    }
    ## Output pixels a glyph's bit covers on a side.
    const DOT := 2
    ## Output pixels between a line and its label, and round the figures.
    const PAD := 2

    ## The picture drawn into, the document region it shows, and the spacing.
    var _image: Image
    ## The picture as it was before a line, which a line's colour is chosen
    ## against, so where two lines cross the second does not read the first.
    var _under: Image
    var _region: Rect2i
    var _spacing: int

    func _init(image: Image, region: Rect2i, spacing: int) -> void:
        _image = image
        _under = image.duplicate() as Image
        _region = region
        _spacing = spacing

    ## Draws every line and then every label, so no line crosses a label.
    func draw() -> void:
        var across := float(_image.get_width()) / float(_region.size.x)
        var down := float(_image.get_height()) / float(_region.size.y)
        var columns := _multiples(_region.position.x, _region.end.x)
        var rows := _multiples(_region.position.y, _region.end.y)
        for x: int in columns:
            var at := floori((x - _region.position.x) * across)
            for y in _image.get_height():
                _contrast(at, y)
        for y: int in rows:
            var at := floori((y - _region.position.y) * down)
            for x in _image.get_width():
                _contrast(x, at)
        for x: int in columns:
            _label(str(x), Vector2i(floori((x - _region.position.x) * across) + PAD, PAD))
        for y: int in rows:
            _label(str(y), Vector2i(PAD, floori((y - _region.position.y) * down) + PAD))

    ## The multiples of the spacing from *from* up to but not including *to*.
    func _multiples(from: int, to: int) -> Array[int]:
        var found: Array[int] = []
        var at := ceili(float(from) / float(_spacing)) * _spacing
        while at < to:
            found.append(at)
            at += _spacing
        return found

    func _contrast(x: int, y: int) -> void:
        var under := _under.get_pixel(x, y)
        _image.set_pixel(x, y, Color.BLACK if under.get_luminance() >= 0.5 else Color.WHITE)

    ## *text* on a black box with its top left corner at *corner*, cut where
    ## the picture ends.
    func _label(text: String, corner: Vector2i) -> void:
        var glyph := 3 * DOT
        var box := Rect2i(corner, Vector2i(text.length() * (glyph + DOT) - DOT + 2 * PAD, 5 * DOT + 2 * PAD))
        box = box.intersection(Rect2i(Vector2i.ZERO, _image.get_size()))
        if box.size.x <= 0 or box.size.y <= 0:
            return
        _image.fill_rect(box, Color.BLACK)
        for i in text.length():
            var bits: Array = GLYPHS.get(text[i], [])
            var left := corner + Vector2i(PAD + i * (glyph + DOT), PAD)
            for row in bits.size():
                for column in 3:
                    if (int(bits[row]) >> (2 - column)) & 1 == 1:
                        var dot := Rect2i(left + Vector2i(column * DOT, row * DOT), Vector2i(DOT, DOT))
                        _image.fill_rect(dot.intersection(box), Color.WHITE)


## Where a `look` step writes *path*: as it is when the engine reads it as
## absolute, and under *folder* when it does not, or when there is no folder.
##
## `String.is_absolute_path` answers the same on every platform, for a leading
## slash or backslash, for `user://` and `res://`, and for a drive letter, so a
## suite on Linux holds what a Windows client sends.
static func look_path(folder: String, path: String) -> String:
    if folder.is_empty() or path.is_absolute_path():
        return path
    return folder.path_join(path)


## Starts a new document: in a named colour space, where File > New puts one
## once its dialog has been confirmed, in the document in front when that is
## untouched, and otherwise in a fresh tab beside it.
##
## The dialog's own dropdowns cannot be reached from a scenario, for the same
## reason its menu item cannot, so this starts where the dialog hands off. It is
## the only way a capture can look at a document that is not sRGB, and looking is
## the whole point: a new Oklab document opened orange, and no test noticed
## because the wrong numbers were a correct fill of the wrong colour.
##
## `"background"` beside it is what the dialog's three background rows hand on,
## `{"document": "srgb", "background": {"kind": "colour", "color": "#e8dcc4",
## "ground": "paper"}}`, the colour as the swatch shows it and the ground a
## registered type's id. Without it the document is a plain grey one.
##
## `"size"` beside it is the canvas the document opens at, `[1920, 1080]` or
## `"default"`, the size File > New offers, which `sara.init()` asks for. Without
## it the document takes the size of the canvas in front. A
## pair with a side outside what File > New allows is refused by `SizeCheck`.
func new_document(space_id: String, background: Dictionary = {}, size: Variant = null) -> void:
    var target: SaColorSpace = null
    for preset: SaColorSpace in SaColorSpace.presets():
        if String(preset.id) == space_id:
            target = preset
    if target == null:
        push_warning("SaCapture: no colour space called '%s'" % space_id)
        return
    # Before anything is reset, so a refused size leaves the open document whole.
    if SizeCheck.is_pair(size) and not SizeCheck.refusal("document %s" % space_id, size as Array).is_empty():
        return
    var wanted := size_of(size)
    var front := CanvasDriver.main_canvas()
    # The verdict a door client reads to tell the step ran from one skipped.
    if front == null:
        push_warning("SaCapture: document %s made nothing, no document in front to make it in" % space_id)
        return
    var opened := wanted if wanted != Vector2i.ZERO else front.canvas_size
    var canvas := SaDocumentFiles.canvas_for_new(_run.tree(), front, opened)
    if canvas == null or canvas.document == null:
        push_warning("SaCapture: document %s made nothing, the card has no room for another document" % space_id)
        return
    canvas.document.reset_to_default(opened, target, SaDocument.DEFAULT_DPI, _background_of(background), _layer_types())
    # Without a size it is the same one, but resize_canvas is what re-derives
    # the output texture's format from the document this reset just changed,
    # and rebinds the view to it. Skipping it is dormant only because every
    # preset here is F32 today: the moment one of them names F16, this canvas
    # would join the one MainCanvas hit, composited forever and shown never.
    canvas.resize_canvas(opened)
    print("SaCapture: document %s, a new %dx%d canvas" % [space_id, opened.x, opened.y])


## The step's `size` as a canvas size, `"default"` the New Document dialog's and
## a pair its own, and anything else zero, which keeps the size already there.
static func size_of(spec: Variant) -> Vector2i:
    if spec is String and String(spec) == "default":
        return NewDocumentDialog.DEFAULT_SIZE
    var pair: Array = spec if spec is Array else []
    return Vector2i(int(pair[0]), int(pair[1])) if pair.size() == 2 else Vector2i.ZERO


## The step's background in `SaDocumentBackground`'s terms, the colour read from
## the `#rrggbb` a scenario writes. Empty stays empty, which is the grey.
static func _background_of(spec: Dictionary) -> Dictionary:
    if spec.is_empty():
        return {}
    var choice := SaDocumentBackground.default_choice()
    choice[SaDocumentBackground.KIND] = StringName(String(spec.get("kind", SaDocumentBackground.COLOUR)))
    if spec.has("color"):
        choice[SaDocumentBackground.COLOR] = Color.html(String(spec["color"]))
    choice[SaDocumentBackground.GROUND] = StringName(String(spec.get("ground", "")))
    return choice


## The app's layer types, where a ground is looked up, or null outside the app.
func _layer_types() -> SaLayerTypeRegistry:
    var main_node: Node = _run.tree().current_scene
    var registries: SaRegistries = main_node.get("registries") if main_node != null else null
    return registries.layer_types if registries != null else null


## Opens a saved document: a `.sad` into the main canvas, the way File > Open
## does once its dialog has been confirmed.
##
## Here for the same reason `document` is, one level in from a click that cannot
## land: the menu item lives in an embedded subwindow and an injected click does
## not route into one. Without it the only way to answer "does this file open
## and show anything" was to decode the file by hand, and a fixture whose painted
## chunks all sat outside the canvas shipped exactly because nobody could look.
##
## A recovery copy beside the file and at least as new names itself in a second
## line, which the door's answer carries among its verdicts.
##
## A load that took sets `last_load`'s `loaded`, the path as Sara read it, and
## `canvas`, the document's size, and a named copy sets `recovery`, its path on
## the machine. `lines` holds every verdict line the load printed, the loaded
## line first, and the door's answer opens its verdicts with them, because an answer
## that held the copy's line and not the loaded one would let a script that
## waits for the words read a good load as a failed one.
##
## The plain form reads the whole file before the step returns. The form with
## `over_frames` reads it as File > Open does, over as many frames as its
## layers take, the window drawing between them, and the step returns at once:
## the scenario waits on frames until the line `SaCapture: loaded` is printed,
## which a perf window around the step and its waits measures. The door reads
## every `load` over frames unless it says `"over_frames": false`, and answers
## once the file is in, [method as_the_door_runs].
##
## `{"load": "res://tests/data/painted_two_layers.sad"}`,
## `{"load": {"path": "/abs/deep.sad", "over_frames": true}}`.
##
## A file that is not there, cannot be opened or is not a `.sad` at all leaves
## the document in front as it was, its layers, pixels and undo history, and
## `last_load` carries an `error` naming the path as Sara read it and why, so
## the door answers `"ok": false`. File > Open reads into a fresh tab and drops
## it on failure, the door has no fresh tab, so the reset `SaSadLettingGo` makes
## would land on the painter's work. A file that opens and fails part way
## may still leave the empty document, and `last_load` says so in `emptied`.
func load_document(spec: Variant) -> void:
    var asked := spec as Dictionary if spec is Dictionary else {}
    var path := String(asked.get("path", "")) if spec is Dictionary else String(spec)
    _run.last_load = {"path": read_as(path)}
    _sized_at_landing = false
    # Into the document in front, the one an Open replaces, and no other.
    var canvas := CanvasDriver.main_canvas()
    if canvas == null:
        _refuse_load("there is no document in front to open %s in." % read_as(path))
        return
    var unopened := why_unopened(path)
    if not unopened.is_empty():
        _refuse_load(unopened)
        return
    if asked.get("over_frames", false):
        SaExport.open_sad(canvas.document, path, _loaded.bind(canvas, path), _landed.bind(canvas))
    else:
        _loaded(SaExport.load_sad(canvas.document, path), canvas, path)


## *step* as the door runs it: a `load` that does not say `over_frames` reads
## over frames, as File > Open does. Read in one call, the structure file of
## 305 layers held one frame of 2.0 s, and the painters' door Saras logged their
## every stall at a load. The door holds the answer until the file is
## in, [method still_loading], so a client still hears "loaded" only once the
## document holds it. A `save` that does not say `over_frames` is written in
## the background as Ctrl+S writes it, since a save at once held one frame of
## 2.2 s on a large document, and the answer waits until the file is whole,
## [method still_saving]. An `export` that does not say `over_frames` is written
## as File > Export writes it, over frames for a PNG, since in one frame it held
## 1.1 s on a large document, and an `autosave` runs as its timer runs it, in
## the background, the answer held for both until the file is whole. Any other
## step comes back as it was.
static func as_the_door_runs(step: Dictionary) -> Dictionary:
    var out := step
    for kind: String in ["export", "autosave"]:
        if out.has(kind) and not out.has("over_frames"):
            out = out.duplicate()
            out["over_frames"] = true
    for kind: String in ["load", "save"]:
        if not out.has(kind):
            continue
        var spec: Variant = out[kind]
        var asked: Dictionary = (spec as Dictionary).duplicate() if spec is Dictionary else {"path": spec}
        if not asked.has("over_frames"):
            asked["over_frames"] = true
        out = out.duplicate()
        out[kind] = asked
    return out


## Whether *step* is a `load` whose file is still being read, which holds the
## door's answer to it.
static func still_loading(step: Dictionary) -> bool:
    return step.has("load") and SaSadFile.opening()


## Whether *step* is a `save`, an `export` or an `autosave` whose file is still
## being written over frames, which holds the door's answer to it until
## `last_save` or `last_export` says how it ended, or the autosave's end line
## is printed.
static func still_saving(step: Dictionary) -> bool:
    if step.has("export"):
        return _exports_on_their_way > 0
    if step.has("autosave"):
        return bool(step.get("over_frames", false)) and SaSadFile.saving()
    return step.has("save") and _saves_on_their_way > 0


## What the `load` step over frames does once the file's stack is in
## *canvas*'s document and its chunks are still to come: the canvas is made
## the document's size, and the part it shows is read first.
func _landed(canvas: SaCanvas) -> Rect2i:
    if not is_instance_valid(canvas) or canvas.document == null:
        return Rect2i()
    print("SaCapture: landed, the view's chunks to come first")
    _sized_at_landing = true
    return SaCanvasView.landed(canvas, canvas.document.canvas_size)


## What the `load` step does once *path* is in *canvas*'s document, or *err*
## says why not.
func _loaded(err: Error, canvas: SaCanvas, path: String) -> void:
    if not is_instance_valid(canvas) or canvas.document == null:
        return
    if err != OK:
        # The file opened as a `.sad` before the reader started, so this came
        # part way through, and `SaSadLettingGo.failed` emptied the document
        # for every error but the two it passes by.
        _run.last_load["emptied"] = err != ERR_SKIP and err != ERR_INVALID_PARAMETER
        _refuse_load("Sara could not read %s (%s)." % [read_as(path), error_string(err)])
        return
    # Made again after the landing made it, the output was cleared and
    # composited whole a second time, budgeted over eight frames of 0.2 to
    # 0.5 s on a large document, which File > Open never pays.
    if not _sized_at_landing:
        canvas.resize_canvas(canvas.document.canvas_size)
    _sized_at_landing = false
    # What File > Open does after its resize: unmarked, the file read unsaved
    # and nameless, and uncleared, Undo listed the last document's steps.
    canvas.document.undo_redo.clear_history()
    canvas.document.history.reset()
    canvas.document.mark_saved(path)
    canvas.request_composite()
    var size := canvas.document.canvas_size
    var line := "SaCapture: loaded %s, canvas %s" % [path, size]
    _run.last_load["loaded"] = read_as(path)
    _run.last_load["canvas"] = [size.x, size.y]
    _run.last_load["lines"] = [line]
    print(line)
    _name_a_newer_copy(path)


## *path* as Sara reads it: a `res://` or `user://` name on the machine, and a
## relative one in Sara's own working folder, which is where it is looked for.
static func read_as(path: String) -> String:
    var machine := ProjectSettings.globalize_path(path)
    var here := DirAccess.open(".") if machine.is_relative_path() else null
    return here.get_current_dir().path_join(machine).simplify_path() if here != null else machine


## Why *path* cannot be opened as a `.sad`, or empty when it can: not there,
## refused by the system, or a file whose first bytes are not a `.sad`'s. Asked
## before the reader runs, because the reader's every failure empties the
## document it was given.
static func why_unopened(path: String) -> String:
    if not FileAccess.file_exists(path):
        return "There is no file %s to load." % read_as(path)
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return "Sara could not open %s (%s)." % [read_as(path), error_string(FileAccess.get_open_error())]
    var magic := file.get_buffer(4).get_string_from_ascii()
    if magic != SaSadFile.SAD_MAGIC_V4:
        return "%s is not a .sad file." % read_as(path)
    return ""


## Ends a `load` step that did not load: the error goes in `last_load`, which
## the door's answer carries with `"ok": false`, and in a verdict line for a
## scenario's log.
func _refuse_load(why: String) -> void:
    _run.last_load["error"] = why
    print("SaCapture: load " + JSON.stringify(_run.last_load))


## Prints the recovery copy beside *path* when it is at least as new as the
## file, so the `load` step's answer tells a client that newer work exists and
## where: a door that closed on idle with unsaved changes kept them there.
## Equal is named, as the autosave's own offer of recoveries
## names it, because the times are whole seconds.
func _name_a_newer_copy(path: String) -> void:
    # Main's autosave, read off its node as the state report reads it: the
    # class is inside `core/sad-file` and its facade does not answer it. The
    # load has just named the document *path*, so its copy is the file's.
    var main_node := _run.tree().current_scene
    if main_node == null or not ("autosave" in main_node) or main_node.autosave == null:
        return
    var copy: String = main_node.autosave.recovery_path()
    if not FileAccess.file_exists(copy) or not FileAccess.file_exists(path):
        return
    if FileAccess.get_modified_time(copy) < FileAccess.get_modified_time(path):
        return
    var at := ProjectSettings.globalize_path(copy)
    var line := "SaCapture: a recovery copy newer than %s is at %s, load it for the unsaved work" % [path.get_file(), at]
    _run.last_load["recovery"] = at
    (_run.last_load["lines"] as Array).append(line)
    print(line)


## Saves, loads or deletes presets: a brush preset, and the library it left is
## printed afterwards. What each preset says it is for is on a line after it.
##
## Here for the same reason `open` and `page` are, one level in from a click that
## cannot land: the preset list lives in a MenuButton's popup, which is a Window,
## and an injected click does not route into one. Without this a capture could
## show that the preset button is drawn and nothing else, and "presets survive a
## restart" would be a claim about the test suite rather than about the app.
##
## `{"preset": {"save": "Inker"}}`, `{"preset": {"load": "Inker"}}`,
## `{"preset": {"delete": "Inker"}}`, `{"preset": {"open": true}}` to pop the
## list open for a shot, or `{"preset": {}}` to list only. `"converter"` is a
## test converter, registered by the function at the end of this file.
## `{"preset": {"star": "Inker"}}` presses that cell's star, a name or a list of
## them, and `{"preset": {"starred": true}}` turns the Starred filter on, both on
## the docker's chooser. `{"preset": {"list": "brush"}}` lists the presets a
## tool or an engine takes, or every one for `""`, each with its engine, tags
## and description, as `SaPresetListDriver` says.
func brush_preset(spec: Dictionary) -> void:
    var bar := _find_tool_options_bar()
    if bar == null:
        push_warning("SaCapture: no tool options bar, so there is nowhere to put a preset")
        return

    if spec.has("save"):
        var stored := bar.save_current_as_preset(String(spec["save"]))
        print("SaCapture: preset save '%s' -> '%s'" % [spec["save"], stored])
    if spec.has("load"):
        print("SaCapture: preset load '%s' -> %s" % [spec["load"], bar.load_preset(String(spec["load"]))])
    if spec.has("delete"):
        bar.load_preset(String(spec["delete"]))
        bar.delete_loaded_preset()
        print("SaCapture: preset delete '%s'" % spec["delete"])
    # The tag row lives in a MenuButton's popup, which is a Window, and an
    # injected click does not route into one.
    if spec.has("tag"):
        bar.filter_by_tag(String(spec["tag"]))
        print("SaCapture: preset tag '%s'" % spec["tag"])
    # `{"preset": {"open": true}}`, so a shot and a dump can show the list
    # itself rather than the button in front of it.
    if bool(spec.get("open", false)):
        MenuDriver.new(_run).open_preset_menu()
    # The chooser, which is the list a painter sees. Every key is applied to
    # whatever is open, so `{"preset": {"open": true, "search": "ink"}}` is one
    # step, and the report goes on the end of whatever this step already printed.
    if spec.has("converter"):
        _register_scenario_converter(spec["converter"])
    if spec.has("list"):
        print(SaPresetListDriver.capture_list(_run.tree(), String(spec["list"])))
    if (
        spec.has("search")
        or spec.has("tag")
        or spec.has("icon_size")
        or spec.has("thumb")
        or spec.has("tags")
        or spec.has("finish")
        or spec.has("star")
        or spec.has("starred")
        or spec.is_empty()
    ):
        print(MenuDriver.new(_run).drive_preset_chooser(spec))

    print(
        (
            "SaCapture: preset library [%s], showing '%s', tagged '%s', from %s"
            % [", ".join(bar.preset_names()), bar.selected_preset_name(), bar.selected_tag(), bar.preset_store.dir]
        )
    )
    # What each preset says it is for, beside the library, so a run reads the
    # sentence its tooltip opens on. `list` gives the same with engines.
    var said := {}
    for preset_name: String in bar.preset_names():
        said[preset_name] = SaPresetStore.description_said(bar.preset_store.about_for(preset_name))
    print("SaCapture: preset descriptions %s" % JSON.stringify(said))


func _find_tool_options_bar() -> ToolOptionsBar:
    for node in _run.tree().root.find_children("*", "HBoxContainer", true, false):
        var bar := node as ToolOptionsBar
        if bar != null:
            return bar
    return null


## Where the last injected event was aimed, in logical units.
##
## `press` and `release` read it rather than DisplayServer.mouse_get_position(),
## which is the *real* pointer. Wayland refuses to warp a client pointer, so that
## is wherever the user's hand left the mouse: a press would land somewhere else
## entirely, and a stroke that never started would look like a broken brush.
##
## Owned here rather than by `sa_capture_input.gd`, because `wheel` writes it too,
## and written by `CaptureInput` on every move it injects (f13).
var last_pointer: Vector2 = Vector2.ZERO


## Steps the document's history, so a scenario can check that a stroke really
## comes back rather than that an undo entry exists.
##
## Straight at the document's UndoRedo rather than through the shortcut, for the
## same reason `open` emits a menu signal: an injected key is a separate question
## from whether the history is right, and only one of them is being asked here.
func history(count: int, backwards: bool) -> void:
    var document := _document()
    if document == null or document.undo_redo == null:
        push_warning("SaCapture: no document to step the history of")
        return
    var moved := 0
    for _i in maxi(count, 1):
        var ok: bool = document.undo_redo.undo() if backwards else document.undo_redo.redo()
        if not ok:
            break
        moved += 1
    print("SaCapture: %s %d of %d step(s)" % ["undo" if backwards else "redo", moved, maxi(count, 1)])


## `{"converter": {"from": "stamp", "to": "noise"}}`, a test converter
## registered through the door the way a module registers one, under a module
## of its own, so the preset menu's Convert to row can be photographed before
## any engine writes a converter of its own. What it answers is a preset of the
## target engine carrying the radius, over a settings script built here that
## declares the engine and nothing else, since no module ships that engine's
## settings yet.
func _register_scenario_converter(spec: Dictionary) -> void:
    var main_node: Node = _run.tree().current_scene
    var registries: SaRegistries = main_node.get("registries") if main_node != null else null
    if registries == null or registries.context == null:
        push_warning("SaCapture: preset converter failed, the app has no registries")
        return
    var to_engine := StringName(String(spec.get("to", "noise")))
    var script := GDScript.new()
    script.source_code = (
        'extends Resource\nconst PRESET_ENGINE: StringName = &"%s"\n@export var radius: float = 0.5\n' % to_engine
    )
    script.reload()
    var converter := func(source: Resource) -> Resource:
        var out := script.new() as Resource
        if "radius" in source:
            out.set("radius", source.get("radius"))
        return out
    var ctx := registries.context.for_module(&"scenario-converter")
    if not ctx.register_converter(StringName(String(spec.get("from", "stamp"))), to_engine, converter):
        push_warning("SaCapture: preset converter failed, the door refused it")
