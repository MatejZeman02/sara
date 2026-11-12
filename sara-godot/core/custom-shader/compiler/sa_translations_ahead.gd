## The kernel files no kept translation answers, translated on the worker pool
## before the kernels stage compiles the first of them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On a start with no translations kept, a fresh install or a dialect that
## changed, translating every file one after another was most of the kernels
## stage: 1.4 seconds of the 3.3 on the RTX 3090's machine, all on the main
## thread. The translation reads its text and nothing else, so the files are
## shared among the pool's threads and the stage compiles from what they made.
##
## A batch in which the dialect raised an error is dropped whole, because an
## error from another thread does not say which file it came from. The stage
## then translates each file on the main thread as it always did, where the
## error is said once and the file it belongs to is never kept.
class_name SaTranslationsAhead
extends RefCounted

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")
const IncludeProcessor := preload("res://core/custom-shader/compiler/sa_include_processor.gd")

## The texts the pool translates, read on the main thread before it starts.
var _texts: Array[String] = []
## What each text read as, filled by the pool, one slot a text.
var _glsl: Array[String] = []
## Where what the pool made is kept between starts.
var _kept: SaGlslCache = null
## The pool's group task, or -1 when there was nothing to translate.
var _task: int = -1
## Hears the dialect's errors on every thread while the pool works.
var _caught: SaErrorCatcher = null


## Starts translating the texts of *paths* that *kept* holds no translation of.
func _init(paths: Array, kept: SaGlslCache) -> void:
    _kept = kept
    for file_path: Variant in paths:
        var file := FileAccess.open(str(file_path), FileAccess.READ)
        if file == null:
            continue
        var text := file.get_as_text()
        if kept.read(text).is_empty() and not _texts.has(text):
            _texts.append(text)
    if _texts.is_empty():
        return
    _glsl.resize(_texts.size())
    # The first text on this thread, because the dialect reads its name table
    # into a static the first time it is asked, and a static two threads fill at
    # once is a race.
    _caught = SaErrorCatcher.listening()
    _glsl[0] = _translated(_texts[0])
    _task = WorkerThreadPool.add_group_task(_translate, _texts.size() - 1, -1, true)


## Whether the pool is done, so the stage may compile. Once it is, every
## translation it made is handed to *source* and kept, unless the dialect raised an
## error meanwhile. *wait* blocks until it is done, for a caller with no
## frames to give.
func finished(source: IncludeProcessor, wait: bool) -> bool:
    if _task < 0:
        return true
    if not wait and not WorkerThreadPool.is_group_task_completed(_task):
        return false
    WorkerThreadPool.wait_for_group_task_completion(_task)
    _task = -1
    _caught.stop()
    if _caught.reports(SaErrorCatcher.ERRORS).is_empty():
        for i in _texts.size():
            source.learn(_texts[i], _glsl[i])
            _kept.keep(_texts[i], _glsl[i])
    _texts.clear()
    _glsl.clear()
    return true


## One text past the first, the one this thread translated.
func _translate(i: int) -> void:
    _glsl[i + 1] = _translated(_texts[i + 1])


static func _translated(text: String) -> String:
    return KernelSource.remove_comments(Dialect.to_glsl(text))
