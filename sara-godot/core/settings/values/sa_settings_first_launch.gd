## The fact Sara keeps about a painter's first answers: whether the welcome
## window has been seen on its Quick settings pane in this profile's life. The
## row "I'm coming from" once kept a second, which of its two buttons for Sara's
## own values was pressed last, and lost it with those buttons, so the
## version-26 step of `SaSettingsMigrations` drops the key.
##
## A first launch opens on the Quick settings pane rather than the recent work
## page, and a first launch is a fact rather than a count of launches. So it is
## one boolean, false in a fresh profile,
## which `SaBoot` reads and the welcome window turns true once it has shown
## the pane. A launch that fails before the window is seen asks again, and a
## reset or a profile that could not be recovered holds it false, as it holds
## every other default.
##
## No page shows it. A file of its own because `SaSettingsValues` stands near
## its thousand lines, the way `SaSettingsIdle` is one.
##
## **It is a link of the settings autoload's chain**: `SaSettings` extends
## `SaSettingsValues` extends `SaSettingsShapeCheck` extends
## `SaSettingsLocation` extends `SaSettingsIdle` extends this extends
## `SaSettingsImporting`, so `SaSettings.first_launch_done` is the property
## below and not a forward to it. It adds no signal, because [signal SaSettingsImporting.changed] is
## the one the rest of the chain shares.
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsFirstLaunch
extends SaSettingsImporting

## Whether the first launch's welcome window has been shown on its Quick
## settings pane. False is a first launch, so the window opens on that pane.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## reads false, so a painter who updates sees the pane once, the language row
## with it, and every launch after that opens on Recent.
var first_launch_done: bool = false:
    set(val):
        if first_launch_done == val:
            return
        first_launch_done = val
        changed.emit(&"first_launch_done")
