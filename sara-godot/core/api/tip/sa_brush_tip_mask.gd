## The GPU side of a tip: the texture an image tip was uploaded into and the
## buffer a soft tip's curve was sampled into.
##
## **It exists to hold a reference, and that is not bookkeeping.** An `SaTexture`
## handed to `SaCompute.set_sampled_texture` and then dropped is freed by RAII
## before the dispatch runs, and the dispatch reports an invalid binding rather
## than painting the wrong thing. So whatever is bound has to be held for as long
## as the tip is selected, and one object holding both is one lifetime rather
## than two fields on a tool that also has a stroke to think about.
##
## **Not a `Resource`.** It is the runtime half of `SaBrushTip`, which is the
## `Resource`: an RID inside a resource would be written into every saved preset
## and would outlive the `RenderingDevice` that made it.
class_name SaBrushTipMask
extends RefCounted

const SaTipImageScript = preload("res://core/api/tip/sa_tip_image.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Where a kernel that draws a tip declares the two things this binds, the soft
## generator's table and the picture. `shaders/compute/libs/brush_tip.gmacs`
## reads both and leaves declaring them to its importer, and `dab.gmacs`
## declares them at these two numbers. Named here rather than written as
## numbers at the call site, because the kernel and this have to agree, and
## named *here* rather than on the tool because this is what binds them.
## `StateBrush` re-exports both under the names the suites use.
const SOFTNESS_BINDING: int = 2
const TIP_IMAGE_BINDING: int = 3

## The image tip's coverage, `r32f`, at the file's own resolution. Null for a
## procedural tip, and one texture serves every size the tip is stamped at:
## the sample coordinate is the dab's own inverse transform, so there is no
## pyramid and no per-size cache.
var texture: SaTexture = null

## The tip's pixel size, kept beside the texture because a dump wants it and
## `SaTexture` is asked for a rid rather than a shape.
var size: Vector2i = Vector2i.ZERO

## Where it came from, so a dump and a preset can both say.
var path: String = ""

## Whether the picture behind this mask carries colour of its own, which is
## the one thing the lightness row is given anything to read.
##
## Read off the loaded tip rather than off the settings, because a brush tip is
## a picture and only the picture knows whether its channels differ: the row
## moves a colour the tip has, and a mask with nothing to say must leave a
## preset that carries the row switched on painting exactly what it painted.
var colourful: bool = false

## Why there is no texture. Empty on success, and the only thing worth reading
## when `texture` is null and `path` is not.
var error: String = ""

## Every cell of a pipe, uploaded once when the pipe is loaded, in file
## order.
##
## Empty for a single picture tip, which is every tip that is not a `.gih`, and
## [member texture] is then the only one there is. For a pipe it holds all of
## them and [member texture] is whichever cell the last dab chose, so everything
## written against one texture, `has_image`, `size` and the dump, keeps
## answering about the picture that was actually stamped.
##
## **Held here for the reason this class exists at all.** A texture handed to
## `set_sampled_texture` and dropped is freed by RAII before the dispatch runs,
## and a pipe drops seven of its eight cells on every dab unless something holds
## the list.
var pipe_cells: Array[SaTexture] = []

## The pipe's own reading of itself, kept because the advance needs its `ranks`
## and its `selections` on every dab and re-reading a file per dab is a file
## read per dab. Null for anything that is not a pipe.
var pipe: SaGihPipe.Pipe = null

## Which cell the last dab chose, an index into [member pipe_cells]. Zero for a
## tip that is not a pipe, where it means the only cell there is.
var pipe_cell: int = 0

## The SOFT generator's falloff, and the samples it was built from. Held here so
## the tool has one object to keep rather than two.
var softness_buffer: SaCompute.Buffer = null
var softness_samples: PackedFloat32Array = PackedFloat32Array()

## What the engine binds beside the tip and has to hold for as long as the tip,
## which this class carries and never reads.
##
## An engine's kernel declares bindings of its own past the tip's two, and a
## buffer bound there is freed by RAII before the dispatch unless something
## holds it, which is this class's reason to exist. So the engine hangs its own
## holder here, the stamp brush its masking block, and it lives exactly as long
## as the tip and carries over a change of picture as the softness table does.
var companion: RefCounted = null

## The one by one stand-in every kernel binding that is not in use gets, which is
## the pattern `SaSelection.everything()` established: a uniform set has to cover
## every binding the shader declares, so a binding with nothing to say binds a
## texel rather than nothing.
##
## **Clear rather than white, which is the opposite of the selection's.** A
## selection that is not there selects everything, and a picture that is not
## there covers nothing: bound white, a tip whose file failed to load paints the
## whole of its own box, which is a solid square where a painter asked for a
## picture and is worse than the refusal it already gets.
##
## Static and shared, because it is one texel and a second copy of it would be a
## second RID for no reason.
static var _stand_in: SaTexture = null


## The one by one clear texel, made once.
static func stand_in() -> SaTexture:
    if _stand_in == null or not _stand_in.rid.is_valid():
        _stand_in = SaTexture.new(Vector2i(1, 1), RenderingDevice.DATA_FORMAT_R32_SFLOAT)
        _stand_in.clear(Color(0.0, 0.0, 0.0, 0.0))
    return _stand_in


## Loads *path* and uploads it, answering a mask whose `error` says why when it
## could not. A path that is empty is a procedural tip and is not an error.
##
## **A load of its own, kept by nobody.** It reads the file, parses it and
## uploads it here and now, by the same steps `SaTipCache` takes off the stroke,
## and hands back the only mask over what it uploaded, so dropping that mask
## gives every texture back. A tool never calls it: [method bind] and
## [method select] ask `SaTipCache`, which keeps what it loads. A suite that
## counts what one load costs calls this.
##
## A `.gih` loads every cell, which `SaTipCache.Picture` says why, because a
## pipe is a collection and `SaTipImage.load_bytes` refuses one by name,
## deliberately and still: the reader reads the container without opening that
## door, and this binds the cells without opening it either.
static func load_image(path_to_read: String) -> SaBrushTipMask:
    if path_to_read.is_empty():
        return SaBrushTipMask.new()
    return SaTipCache.Picture.new(path_to_read).finish()


## Whether *path* names a GIMP pipe, which is the one question three call sites
## ask and the reason it is spelled once.
static func is_pipe_path(path_to_read: String) -> bool:
    return path_to_read.to_lower().ends_with(".gih")


## A mask of its own over this one's pictures, on the first cell, with no
## softness table and no companion yet.
##
## **What `SaTipCache` hands a tool, never the mask it keeps.** A mask is written
## by whoever holds it, its pipe cell on every dab and its table and companion as
## they move, so two tools holding one would advance each other's pipe. The
## textures are shared and `RefCounted`, so a picture the cache drops stays on
## the card for as long as a view of it is held.
func view() -> SaBrushTipMask:
    var fresh := SaBrushTipMask.new()
    fresh.path = path
    fresh.error = error
    fresh.colourful = colourful
    fresh.pipe = pipe
    fresh.pipe_cells = pipe_cells.duplicate()
    fresh.pipe_cell = 0
    fresh.texture = pipe_cells[0] if not pipe_cells.is_empty() else texture
    fresh.size = pipe.tips[0].size if pipe != null and not pipe.tips.is_empty() else size
    return fresh


## Whether this mask is a pipe with cells to choose between.
func has_pipe() -> bool:
    return pipe != null and pipe_cells.size() > 1


## Whether this mask has an image the kernel can sample.
func has_image() -> bool:
    return texture != null and texture.rid.is_valid()


## The painted tip's own lightness row, as the kernel is given it: the setting
## when this mask's picture carries colour and nought when it does not.
##
## **A mask rather than a multiply.** The row is a strength over a channel, and
## a tip with no colour has nothing for it to move, so what travels is the
## neutral value rather than the painter's number. Left in, it would work by
## arithmetic and would read in a dump as a row that applies to a tip it does
## nothing to.
func lightness_strength_for(tip: Resource) -> float:
    if not colourful or tip == null or not "lightness_strength" in tip:
        return 0.0
    return SaTyped.real(tip.get("lightness_strength"))


## The rid the tip sampler binds, which is the stand-in when there is no image.
func sampler_rid() -> RID:
    return texture.rid if has_image() else stand_in().rid


## Points this mask at the cell *info*'s dab asks for, and answers which.
##
## **The whole of the advance, and it moves a reference rather than the GPU.**
## Every cell is already uploaded, so choosing one is an index and an assignment
## to [member texture], and the dispatch that follows binds a different rid. A
## tip that is not a pipe is left exactly as it was, which is what makes a
## one-cell pipe and a single picture the same stroke to the texel.
##
## *info* is null wherever a caller has no stroke, which is every suite that
## dispatches a dab by hand: the cell then stays where it was, because a pipe
## with nothing to advance on is a pipe on its first cell.
func advance(info: SaStrokeInfo) -> int:
    if not has_pipe():
        return pipe_cell
    if info == null:
        return pipe_cell
    pipe_cell = cell_for(pipe, info, pipe_cells.size())
    texture = pipe_cells[pipe_cell]
    size = pipe.tips[pipe_cell].size
    return pipe_cell


## Which cell of *read* the dab described by *info* wants, of *cells* of
## them.
##
## **Each dimension answers its own coordinate and the coordinates are strided
## into one index**, which is the shape GIMP's own pipe has: `dim` dimensions,
## `rank0` upwards saying how many cells each holds, `sel0` upwards saying how a
## dab picks along it.
##
## **Dimension nought varies fastest.** A one-dimensional pipe, which is every
## pipe to be found in the wild and every one the reader's test writes, cannot
## tell the two orders apart, so the choice is free there and this is the order
## the keys are numbered in. If a two-dimensional pipe ever paints its cells in
## the wrong order, this line is the one to turn round, and the record says so
## rather than leaving the next reader to find it.
##
## **Static, and it takes the pipe rather than reading `self`**, so a test can
## ask what a dab would choose without uploading anything to a GPU.
static func cell_for(read: SaGihPipe.Pipe, info: SaStrokeInfo, cells: int) -> int:
    if read == null or cells <= 1:
        return 0
    var index := 0
    var stride := 1
    for d in mini(read.dimension, read.ranks.size()):
        var rank := maxi(1, read.ranks[d])
        var selection: String = read.selections[d] if d < read.selections.size() else SaGihPipe.SELECTION_WHEN_UNSTATED
        index += _coordinate(selection, rank, info) * stride
        stride *= rank
    return clampi(index, 0, cells - 1)


## One dimension's coordinate, which is the whole of what a selection mode
## means.
##
## The eight are `SaGihPipe.SELECTIONS` and every one of them is here, because
## each is a line and a mode that silently did nothing would be a pipe that never
## advanced for a reason nothing reports, which is the failure the reader was
## split off to keep out of a stroke.
##
## - `constant` never moves, and is what an unstated dimension gets.
## - `incremental` steps one cell per dab, which is what an animated pipe is for,
##   and it counts the dabs already painted rather than the ordinal of this one,
##   so a stroke's first dab is the pipe's first cell.
## - `angular` reads the stroke's own direction, so a pipe of arrows points along
##   the line rather than along the page.
## - The other five read a sensor the dynamics half already computes: speed,
##   pressure and the two tilts, each of which is a number this maps onto the
##   dimension's cells.
##
## **`random` draws from the stroke's own per-dab generator**, `SaStrokeInfo`'s
## `random`, which is seeded from the stroke's seed. So the same stroke painted
## twice from the same seed picks the same cells, which is what makes a pipe
## testable at all, and two strokes of one session do not repeat.
static func _coordinate(selection: String, rank: int, info: SaStrokeInfo) -> int:
    if rank <= 1:
        return 0
    match selection:
        "incremental":
            # `dab_index` is one past the count: `SaStrokeInfo.next_dab` adds one
            # before the dab it belongs to is stamped, so the first painted dab
            # reads one. Taking one back here makes the first dab of a stroke the
            # pipe's first cell, which is the picture the first cell's own file
            # paints and what a shorter pipe's later strokes start on. The step
            # is still one per dab, so a four-cell pipe walks 0, 1, 2, 3 and
            # wraps.
            #
            # Clamped at the floor, because a caller that binds with no dab
            # counted yet reads a zero and `posmod(-1, rank)` would be the last
            # cell rather than the first. That caller is the one `advance`
            # describes: a pipe nothing has advanced on is a pipe on its first
            # cell.
            return posmod(maxi(0, info.dab_index - 1), rank)
        "random":
            return info.random.randi_range(0, rank - 1)
        "angular":
            # atan2 answers minus pi to pi and the wedge is measured from zero,
            # so the angle is folded into a full turn before it is bucketed.
            return _bucket(fposmod(info.drawing_angle(false), TAU) / TAU, rank)
        "velocity":
            return _bucket(info.drawing_speed(), rank)
        "pressure":
            return _bucket(info.pressure, rank)
        "xtilt":
            return _bucket(info.tilt_x * 0.5 + 0.5, rank)
        "ytilt":
            return _bucket(info.tilt_y * 0.5 + 0.5, rank)
    return 0


## A nought to one reading as one of *rank* cells, the last of which is what a
## reading of exactly one lands in rather than one past the end.
static func _bucket(fraction: float, rank: int) -> int:
    return clampi(int(clampf(fraction, 0.0, 1.0) * float(rank)), 0, rank - 1)


## Rebuilds the softness table when *tip*'s has moved, and answers the buffer.
##
## The comparison is on the samples rather than on the curve, because a `Curve`
## is a mutable resource the editor writes in place: comparing the object would
## never see a change, and comparing its points would miss the softness
## multiplier that reshapes them.
func softness_for(tip: Resource) -> SaCompute.Buffer:
    var brush_tip: SaBrushTipScript = tip
    var samples := brush_tip.softness_table()
    if softness_buffer == null or samples != softness_samples:
        softness_samples = samples
        softness_buffer = SaCompute.Buffer.new(samples.to_byte_array())
    return softness_buffer


## What a state dump says about this mask.
##
## **No row of texels, and that is hard rule 1 rather than an omission**. A
## profile through a stamped dab is what a reader of the dump would want, and
## the only way to get one from inside the app is `texture_get_data`, which
## `tests/test_hard_rules.gd` allows in the exporter and the eyedropper and
## nowhere else. So the profile is read off the scenario's own shot instead,
## which is the compositor's readback rather than Sara's, and what a dump says
## about a tip is which picture it is and what fade the live brush would send.
func report(settings: Resource = null) -> Dictionary[String, Variant]:
    var held: Variant = settings.get("tip") if settings != null and "tip" in settings else null
    var tip: SaBrushTipScript = held if held is SaBrushTipScript else null
    var fade: Vector2 = tip.effective_fade() if tip != null else Vector2.ZERO
    return {
        "path": path,
        "width": size.x,
        "height": size.y,
        "has_image": has_image(),
        "error": error,
        "live_fade": [fade.x, fade.y],
        # Whether the picture behind the mask carries colour of its own, which
        # is what the lightness row reads. A dump cannot show the shift
        # itself, since the texels it moves are on the canvas.
        "colourful": colourful,
        "lightness_strength": lightness_strength_for(tip),
        # The pipe. Zero cells is every tip that is not one, so a dump says which
        # of the two a stroke was painted with without a flag, and `cell` is the
        # picture the last dab actually stamped.
        "pipe_cells": pipe_cells.size(),
        "pipe_cell": pipe_cell,
        "pipe_selections": Array(pipe.selections) if pipe != null else [],
        "pipe_ranks": Array(pipe.ranks) if pipe != null else [],
        # What the app's tools share of loaded pictures, so a dump says whether
        # a press found its picture kept or had to read it.
        "cache": SaTipCache.shared().report(),
    }


## Where a tip may be found: the ones Sara ships and the ones a painter has
## saved.
##
## Two folders rather than one, for the reason the preset store has two: what
## ships is read-only and lives in the project, and what a painter loads is
## theirs and lives beside their settings. Both are scanned so a Tip row can
## offer either without knowing which is which.
const SHIPPED_DIR := "res://tips"
## The painter's folder, a name under the data root that `--settings-dir`
## moves, asked through [method saved_dir].
const SAVED_FOLDER := "brush_tips"

## Extensions the tips folders list: a `.gih` is a pipe the pipe reader takes,
## and an `.abr` is a collection Load Tip opens in `SaAbrChooser` instead.
const READABLE := ["png", "gbr", "gih"]


## The folder a painter's tips are read from and written to.
static func saved_dir() -> String:
    return SaDataRoot.path(SAVED_FOLDER)


## The bytes of a tip a preset embedded, written into [method saved_dir] under
## *file_name* and answered by path, or empty when there is nothing to write or
## the folder cannot be made. The one door into the tips folder, so a tip file
## has one writer: [method select] and [method available] read back what this
## writes, and the Krita import writes a tip and the masking brush's own tip
## through it.
static func save(file_name: String, bytes: PackedByteArray) -> String:
    if bytes.is_empty() or file_name.is_empty():
        return ""
    var saved := saved_dir()
    if DirAccess.make_dir_recursive_absolute(saved) != OK and not DirAccess.dir_exists_absolute(saved):
        return ""
    var written := saved.path_join(file_name.validate_filename())
    var file := FileAccess.open(written, FileAccess.WRITE)
    if file == null:
        return ""
    file.store_buffer(bytes)
    file.close()
    return written


## Every tip on disk, as `{path: name}`, shipped first and then saved.
##
## Sorted inside each folder so a chooser's order is the same on every machine,
## which a `DirAccess` listing is not.
static func available() -> Dictionary[String, String]:
    var found: Dictionary[String, String] = {}
    for folder: String in [SHIPPED_DIR, saved_dir()]:
        if not DirAccess.dir_exists_absolute(folder):
            continue
        var names := Array(DirAccess.get_files_at(folder))
        names.sort()
        for file: String in names:
            # An exported build ships `.import` beside the real file, and a
            # `.png.import` is not a tip.
            var clean := file.trim_suffix(".import")
            if not READABLE.has(clean.get_extension().to_lower()):
                continue
            found[folder.path_join(clean)] = clean.get_basename().capitalize()
    return found


## The pictures [method select] loaded from outside the two folders this run,
## the first load first. One that Load Tip read from anywhere left the Tip Image
## grid once the brush moved off it, and a painter went back to find it on disk.
## Kept for the run only: a preset keeps its path, and a picture wanted for good
## belongs in a tip folder.
static var _loaded_elsewhere: Array[String] = []


## The pictures loaded from elsewhere that are still on disk.
static func loaded_elsewhere() -> Array[String]:
    var out: Array[String] = []
    out.assign(_loaded_elsewhere.filter(func(loaded: String) -> bool: return FileAccess.file_exists(loaded)))
    return out


## Forgets them, for a suite that lists from the folders alone.
static func forget_loaded_elsewhere() -> void:
    _loaded_elsewhere.clear()


## Binds the tip's two and answers the mask to hold on to.
##
## *held* is what the tool bound last time. The image is asked for only when the
## path moves, because this runs once per dab, and then of `SaTipCache`, which
## answers a picture already on the card without reading anything and finishes a
## load a chosen preset began. The stand-in goes on the picture's binding when there is no picture,
## which a uniform set covering every declared binding makes necessary rather
## than tidy. A kernel that declares more than the tip's two binds the rest
## itself after this, as the stamp brush's `SaStampBindings.bind` does.
static func bind(compute: SaCompute, tip: Resource, held: SaBrushTipMask, info: SaStrokeInfo = null) -> SaBrushTipMask:
    var brush_tip: SaBrushTipScript = tip
    var wanted: String = brush_tip.image_path if brush_tip.uses_image() else ""
    var mask := held
    if mask == null or mask.path != wanted:
        mask = SaTipCache.shared().mask_for(wanted)
        if held != null and not held.softness_samples.is_empty():
            # The curve did not move because the picture did, so the buffer
            # carries over rather than being rebuilt on the next dab.
            mask.softness_buffer = held.softness_buffer
            mask.softness_samples = held.softness_samples
        if held != null and held.companion != null:
            # What the engine holds beside the tip did not move because the
            # picture did either, and carried over it is a uniform set that
            # does not have to be rebuilt on the dab after a tip change.
            mask.companion = held.companion
        if not mask.error.is_empty():
            EventBus.paint_refused.emit(mask.error)
    # The pipe's cell for this dab, chosen before the sampler is bound and after
    # any reload, so a stroke that changed tips advances the tip it has. A tip
    # that is not a pipe answers its only cell and binds what it bound before.
    mask.advance(info)
    compute.set_buffer(SOFTNESS_BINDING, mask.softness_for(tip).rid)
    compute.set_sampled_texture(TIP_IMAGE_BINDING, mask.sampler_rid())
    return mask


## Loads *path* onto *tip* and answers the mask, whose `error` says why when it
## could not and whose caller reports it.
##
## Both fields move together or neither does, which is the whole point of one
## function: `generator` is what the kernel branches on and `kind` is the record
## beside it, and a path that loaded nothing leaves the tip exactly as it was. A
## pipe reaches this door the way a picture does, and `has_image` is true
## because a pipe's first cell is a picture. So the Tip row, the Load Tip
## action, a scenario and the import all gain pipes without any of them learning
## what one is.
##
## Through `SaTipCache`, so what the import loads to check a tip is kept, and
## the first press with the preset it made binds it without a load.
static func select(tip: Resource, from_path: String) -> SaBrushTipMask:
    var mask := SaTipCache.shared().mask_for(from_path)
    if not mask.error.is_empty():
        return mask
    var brush_tip: SaBrushTipScript = tip
    brush_tip.image_path = from_path
    # A picture from outside the folders stays in the Tip Image grid for the run.
    if from_path.get_base_dir() not in ["", SHIPPED_DIR, saved_dir()] and not _loaded_elsewhere.has(from_path):
        _loaded_elsewhere.append(from_path)
    if mask.has_image():
        brush_tip.kind = SaBrushTipScript.Kind.IMAGE
        brush_tip.generator = SaDabGeometry.Generator.IMAGE
    else:
        brush_tip.kind = SaBrushTipScript.Kind.PROCEDURAL
    return mask


## The Load Tip picker's filters, through `TranslationServer` in a static.
static func load_filters() -> PackedStringArray:
    return PackedStringArray(
        [
            TranslationServer.translate("*.png, *.gbr, *.gih, *.abr ; Brush Tip"),
            TranslationServer.translate("*.png ; PNG"),
            TranslationServer.translate("*.gbr ; GIMP Brush"),
            TranslationServer.translate("*.gih ; GIMP Pipe"),
            TranslationServer.translate("*.abr ; Photoshop Brushes"),
        ]
    )


## Opens the Load Tip picker and hands the chosen path to *on_chosen* once
## its picture is on the card. An `.abr` opens the chooser first, asked of the
## interface through `SaDialogsInHand`, whose pick is written as a `.png` and
## handed on by that path. Asked of the root, since
## a tool is a `RefCounted`. **The load goes off the stroke first**, the road a
## chosen preset takes: the file is read on a worker and uploaded a few cells a
## frame by `SaTipCache.ahead`, and *on_chosen* is called when that is done, so
## the [method select] it makes finds the picture kept and the window never
## stops.
static func choose_file(on_chosen: Callable) -> void:
    var loop := Engine.get_main_loop() as SceneTree
    if loop == null or loop.root == null:
        return
    var title := TranslationServer.translate("Load Brush Tip")
    var loaded := func(chosen: String) -> void: SaTipCache.shared().ahead(chosen, on_chosen.bind(chosen))
    SaFilePicker.open(loop.root, SaFilePicker.Mode.OPEN_FILE, load_filters(), SaDialogsInHand.abr_ahead_of(loaded), title)
