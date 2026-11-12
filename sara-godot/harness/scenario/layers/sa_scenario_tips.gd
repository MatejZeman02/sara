## The brush tips a scenario paints with that are too large to keep in the tree.
##
## A tip's load is timed on a pipe the size of the largest knife a painter
## brings, 360 cells of 256 by 256, which is 23 MB of file. So it is written at the step,
## the way a suite builds the files it reads, by the `brush` step's `tip_pipe`
## key, and the suite beside `sa_tip_cache.gd` writes its own through
## [method write_pipe] as well, so the two read one shape of file.
class_name SaScenarioTips
extends RefCounted

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")


## The tip fields of a pipe written for the `brush` step's `tip_pipe` key: a
## GIMP pipe of `cells` cells of `side` by `side` written into the painter's
## tips folder as `file`, and the fields that point a tip at it the way a preset
## naming it would, `{"file": "knife.gih", "cells": 360, "side": 256}`.
##
## Fields only, so nothing reads the pipe and a preset saved next is a preset
## whose tip nothing has loaded yet, which is what a timed load needs.
## Empty when the file could not be written.
static func pipe(spec: Dictionary) -> Dictionary:
    var folder := SaBrushTipMask.saved_dir()
    DirAccess.make_dir_recursive_absolute(folder)
    var path := write_pipe(
        folder.path_join(String(spec.get("file", "pipe.gih"))), int(spec.get("cells", 4)), int(spec.get("side", 64))
    )
    if path.is_empty():
        return {}
    return {
        "tip:image_path": path,
        "tip:kind": SaBrushTipScript.Kind.IMAGE,
        "tip:generator": SaDabGeometry.Generator.IMAGE,
    }


## A `.gih` of *cells* cells of *side* by *side* at *path*, stepping one cell a
## dab, each a version 2 GBR of one byte a texel whose coverage is its own, and
## the path, or empty when it could not be written.
static func write_pipe(path: String, cells: int, side: int) -> String:
    var line := (
        "%d ncells:%d cellwidth:%d cellheight:%d step:20 dim:1 cols:1 rows:%d placement:constant rank0:%d sel0:incremental"
        % [cells, cells, side, side, cells, cells]
    )
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return ""
    file.store_buffer(("%s\n%s\n" % [path.get_file().get_basename(), line]).to_utf8_buffer())
    for index in cells:
        file.store_buffer(_gbr("cell %d" % index, side, 1 + index % 255))
    file.close()
    return path


## A version 2 GBR of *side* by *side*, one byte a texel, every texel *value*.
static func _gbr(tip_name: String, side: int, value: int) -> PackedByteArray:
    var named := tip_name.to_utf8_buffer()
    var header := PackedByteArray()
    for word: int in [28 + named.size() + 1, 2, side, side, 1, SaTipImage.GBR_MAGIC, 20]:
        header.append_array(_be(word))
    header.append_array(named)
    header.append(0)
    var coverage := PackedByteArray()
    coverage.resize(side * side)
    coverage.fill(value)
    header.append_array(coverage)
    return header


static func _be(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])
