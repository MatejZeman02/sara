## The kernel files translated on the worker pool before the kernels stage read
## as each one translated on the main thread does, and are kept between starts.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const IncludeProcessor := preload("res://core/custom-shader/compiler/sa_include_processor.gd")
const ShaderIndex := preload("res://core/custom-shader/compiler/sa_shader_index.gd")
const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## A handful of the tree's own kernels, the largest among them, and a library.
const PATHS: Array[String] = [
    "res://shaders/compute/graph.gmacs",
    "res://shaders/compute/selection.gmacs",
    "res://shaders/compute/libs/composite_blend_modes.gmacs",
]

static var scratch: String = SaDataRoot.path("test_translations_ahead")


func after_each() -> void:
    var folder := ProjectSettings.globalize_path(scratch)
    DirAccess.remove_absolute(folder.path_join(SaGlslCache.CACHE_FILE))
    DirAccess.remove_absolute(folder)


func test_each_file_reads_as_its_translation_in_turn() -> void:
    var kept := SaGlslCache.new(scratch, "probe dialect")
    var ahead := SaTranslationsAhead.new(PATHS, kept)
    var source := IncludeProcessor.new(ShaderIndex.new())
    assert_true(ahead.finished(source, true), "A wait ends with the pool done")
    for file_path: String in PATHS:
        var text := FileAccess.get_file_as_string(file_path)
        var in_turn := KernelSource.remove_comments(Dialect.to_glsl(text))
        assert_false(in_turn.is_empty(), "%s translates" % file_path)
        assert_eq(source.glsl_of(text), in_turn, "%s reads as it does translated on this thread" % file_path)
        assert_eq(kept.read(text), in_turn, "and is kept for the next start")


func test_a_file_already_kept_is_not_translated_again() -> void:
    var kept := SaGlslCache.new(scratch, "probe dialect")
    var text := FileAccess.get_file_as_string(PATHS[0])
    kept.keep(text, "kept glsl")
    var source := IncludeProcessor.new(ShaderIndex.new())
    var ahead := SaTranslationsAhead.new([PATHS[0]], kept)
    assert_true(ahead.finished(source, false), "Nothing to translate is done at once")
    assert_eq(kept.read(text), "kept glsl", "and what was kept stays")
