## The settings of the jobs that wait for the painter: how long the painter has
## to leave the document alone before Sara counts them as having stopped.
##
## The wait is one shared setting, "idle after", five seconds by default, so the
## numbers of the stats docker and the autosave's quiet time read it, and the
## thumbnails can read it later, without a wait of their own each. What counts
## as an edit is `SaIdleClock`'s business, and this class holds only the
## seconds.
##
## **It is a link of the settings autoload's chain**: `SaSettings` extends
## `SaSettingsValues` extends `SaSettingsShapeCheck` extends
## `SaSettingsLocation` extends this extends `SaSettingsFirstLaunch`, so
## `SaSettings.idle_after_seconds` is the property below and not a forward to
## it. It adds no signal, because [signal SaSettingsImporting.changed] is the
## one the rest of the chain shares. The preferences that follow it in the
## family of jobs that wait for the painter go beside it.
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsIdle
extends SaSettingsFirstLaunch

## The shortest and the longest a hand may set, in seconds. Below a second a
## pause between two strokes would count as having stopped, and above a minute
## the numbers would trail the picture.
const MIN_IDLE_SECONDS: float = 1.0
const MAX_IDLE_SECONDS: float = 60.0

## Seconds with no stroke, fill or layer change before every idle job is told
## the painter has stopped. A pan, a zoom, a rotation or a change of view mode
## is not an edit and does not restart the wait.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## reads the five seconds a new one has.
var idle_after_seconds: float = 5.0:
    set(val):
        val = clampf(val, MIN_IDLE_SECONDS, MAX_IDLE_SECONDS)
        if is_equal_approx(idle_after_seconds, val):
            return
        idle_after_seconds = val
        changed.emit(&"idle_after_seconds")
