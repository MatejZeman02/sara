## The one bake of `SaGamutPreview.picture()` a session needs, run on a worker
## thread for the Display page's pair of previews.
##
## A preview bakes the picture as it enters the tree when it has no texture, and
## that bake is about 170 ms of arithmetic. On the main thread it was most of
## the first open of Help > Display Settings, a frame of 340 to 370 ms.
## Here it runs beside the frames, the pair shows a blank stand-in for the few
## frames it takes, and the Tonemap dialog, which asks `picture()` the same way,
## finds it baked.
##
## Static, because every Display page shares the one picture, and a page opened
## while the last one's bake runs waits for that bake rather than starting a
## second.
class_name SaGamutPictureBake
extends RefCounted

## The bake in flight, or -1.
static var _task := -1
## Whether `SaGamutPreview.picture()` now answers without baking.
static var _done := false


## Puts the picture on every preview of *halves* when it is in, and true. While
## it is not, starts the bake if nothing has, gives each preview with no texture
## the blank stand-in, so its own `_enter_tree` does not bake on the main thread
## after all, and false. Asked again each frame until it answers true.
static func dress(halves: Array) -> bool:
    if not _done and _task != -1 and WorkerThreadPool.is_task_completed(_task):
        finish()
    if _done:
        for half: SaGamutPreview in halves:
            if half != null and half.texture is PlaceholderTexture2D:
                half.texture = SaGamutPreview.picture()
        return true
    if _task == -1:
        _task = WorkerThreadPool.add_task(SaGamutPreview.picture, false, "the gamut preview's picture")
    var blank := PlaceholderTexture2D.new()
    blank.size = Vector2(SaGamutPreview.TEXELS)
    for half: SaGamutPreview in halves:
        if half != null and half.texture == null:
            half.texture = blank
    return false


## Waits for a bake in flight, and marks the picture in. What a page leaving the
## tree mid-bake calls, since a task nobody waits for is an engine error at exit.
static func finish() -> void:
    if _task == -1:
        return
    WorkerThreadPool.wait_for_task_completion(_task)
    _task = -1
    _done = true
