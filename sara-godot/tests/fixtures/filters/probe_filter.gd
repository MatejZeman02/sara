## Just enough of a filter to call, its one abstract method.
##
## A file of its own rather than an inner class of the suite, because
## `SaFilterApply.source_of` answers with a script's path and the line its `run`
## starts on, and an inner class would have it pointing at the test.
extends SaFilter

## When true the run comes back having shown nothing, which is what a run that
## died halfway looks like from the outside.
var quiet: bool = false


func run(ctx: SaFilterContext) -> void:
    if quiet:
        return
    ctx.show(ctx.blank_like(ctx.layer_pixels(0)))
