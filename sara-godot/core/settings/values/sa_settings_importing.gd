## The preferences about bringing a picture in: how an import is fitted, the
## depth an opened picture is stored at, and whether opening asks about it.
##
## Its own class so that `SaSettingsValues` has room for the preferences that
## follow, and a family rather than three loose properties because the three
## are one subject: what happens to a picture that is not a document yet.
## The first two moved out of the values and the third was added with them.
##
## **It is a link of the settings autoload's chain**, `SaSettings` extends
## `SaSettingsValues` extends this, so `SaSettings.import_fit` is the property
## below and not a forward to it. It declares [signal changed] for that reason,
## because a setter here has to say which preference moved and the values below
## it share the signal. The preferences that follow go beside these.
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsImporting
extends Node

## Which preference moved, by property name. The one signal the file and the
## apply half listen to.
signal changed(property: StringName)

## How a picture whose size differs from the canvas is placed, as one of
## `IMPORT_FITS`. "ask" opens the dialog, and the other four are what the
## painter chose there with "Do not ask again" ticked.
##
## Additive, and without a SETTINGS_VERSION bump: an older profile has no key
## and is asked, which is the default anyone new gets too.
var import_fit: String = "ask":
    set(val):
        import_fit = val if IMPORT_FITS.has(val) else "ask"
        changed.emit(&"import_fit")

const IMPORT_FITS: Array[String] = ["ask", "stretch", "actual", "inside", "grow"]

## Which float depth an opened picture that names none is stored at, as one of
## `IMPORT_DEPTHS`. The painter's last answer rather than a policy: a file that
## names its own width never writes this.
##
## There is no "ask" here the way there is above. Whether the question is asked
## at all is `ask_when_opening`'s, and this is only what the question starts on
## and what a skipped one answers with.
##
## Additive, without a SETTINGS_VERSION bump. F16, half the memory and still
## float. A stored "f32" is kept, since it cannot be told from an answer.
var import_depth: String = "f16":
    set(val):
        import_depth = val if IMPORT_DEPTHS.has(val) else "f16"
        changed.emit(&"import_depth")

const IMPORT_DEPTHS: Array[String] = ["f32", "f16"]

## Whether opening a picture as a document asks about its colour space and bit
## depth first. On, the window shows for every picture. Off, the picture opens
## straight away with the answers the window would have opened on: the file's
## own gamut and float width when it names them, and otherwise the convention
## for its format and `import_depth`.
##
## The window carries the switch as "Show this next time" and Preferences >
## Files has the row that brings the question back. A habit rather than one
## document's cost, because the window is too much for artists who open a
## picture to paint on it. `import_depth`
## stays what a skipped question answers with when the file is silent.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and is
## asked, which is the default anyone new gets too.
var ask_when_opening: bool = true:
    set(val):
        if ask_when_opening == val:
            return
        ask_when_opening = val
        changed.emit(&"ask_when_opening")

## Whether an eight-bit picture asks the question too, the switch Preferences >
## Files calls asking every time. Off, a JPEG, an eight-bit PNG or a WebP opens
## at once at `import_depth` in the gamut the window would have offered first,
## because a file of bytes has no float width to ask about and Photoshop asks
## nothing about one. On, it asks as a float file does. Either way
## `ask_when_opening` off asks about nothing.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## opens its eight-bit pictures at once, which is the default anyone new gets.
var ask_eight_bit_when_opening: bool = false:
    set(val):
        if ask_eight_bit_when_opening == val:
            return
        ask_eight_bit_when_opening = val
        changed.emit(&"ask_eight_bit_when_opening")

## Whether opening a picture exactly twice as wide as it is tall asks if it is
## an equirectangular panorama. On, the question comes once the picture has
## landed, Keep Flat its default. Off, the picture opens flat and nothing is
## asked, and Image > Projection... assigns the kind later.
##
## Here because it is the third thing that happens to a picture that is not a
## document yet, beside the depth and the question about it, and its row sits
## under theirs on Preferences > Files.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## is asked, which is the default anyone new gets too.
var ask_panorama: bool = true:
    set(val):
        if ask_panorama == val:
            return
        ask_panorama = val
        changed.emit(&"ask_panorama")

## Whether a filter's "Preview on canvas" switch starts on when its window
## opens. On by default, the switch the dialog has always had. The settings for
## a weak GPU write it off and Defaults writes it back on: off by default only
## when toaster mode is on.
## It is a preference and not a mode, so a painter may move it alone, and the
## switch on the window stays live either way: this is only where it starts.
##
## It sits in this class for room, not for its subject. `SaSettingsValues` has
## none left, and this is the class the next preferences go in.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## starts the preview on, which changes nothing for it.
var filter_preview_on_canvas: bool = true:
    set(val):
        if filter_preview_on_canvas == val:
            return
        filter_preview_on_canvas = val
        changed.emit(&"filter_preview_on_canvas")

## The way a filter's Apply takes, as one of `FILTER_WAYS`: the last one a hand
## picked on the Bake, Attach, Layer and Picture toggle in a filter's window, shared by
## every filter and kept across sessions, so a choice stays until it is changed,
## and Layer picked in one filter opens the next on Layer. Bake is what a fresh
## profile opens on, for the reason `SaFilterDialogWindow.WAYS` gives.
##
## Only a hand's pick writes it. A window that opens where the remembered way is
## dimmed, Bake on a locked layer, settles its thumb on the first open way and
## leaves this as it was, so the next filter that can take it opens on it again.
##
## It sits in this class for room, as `filter_preview_on_canvas` does.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## opens on Bake, which changes nothing for it.
var filter_way: String = "bake":
    set(val):
        val = val if FILTER_WAYS.has(val) else "bake"
        if filter_way == val:
            return
        filter_way = val
        changed.emit(&"filter_way")

const FILTER_WAYS: Array[String] = ["bake", "attach", "layer"]

## Whether a filter's Apply reaches the whole picture, the Affect all check
## beside the way toggle in a filter's window: Bake writes every paint layer,
## Attach hangs the record on the document and Layer puts the adjustment layer
## at the top of the stack. Off on a fresh profile, because a filter changes the
## active layer or a group, and all only when it is the global one. Remembered
## as `filter_way` is, only a hand's tick writes it, and it sits in this class
## for the same room.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## opens with the check off, which changes nothing for it.
var filter_affect_all: bool = false:
    set(val):
        if filter_affect_all == val:
            return
        filter_affect_all = val
        changed.emit(&"filter_affect_all")
