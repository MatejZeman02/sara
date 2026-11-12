## Whether opening a picture as a document asks which depth to keep it at, and
## the answer when it does not.
##
## A file of bytes, a JPEG, an eight-bit PNG or a WebP, names no float width,
## so there is nothing in it to ask about, and a question on every open would
## be the first thing a painter coming from Photoshop met. Such a
## file opens at once at `SaImportFitDialog.remembered_depth()` in the gamut the
## window would have offered first. A float file still asks, under
## `SaSettings.ask_when_opening`, and an eight-bit one asks as well only when
## Preferences' `SaSettings.ask_eight_bit_when_opening` is on.
##
## Beside `SaOpenRoute` because it is the next thing File > Open decides about
## a picture, after which loader reads it.
class_name SaOpenDepth
extends RefCounted


## Hands *done* the colour space *image*, read from *path*, becomes a document
## in, at once or after the question `host` shows.
static func ask(host: Node, path: String, image: Image, done: Callable) -> void:
    var named := SaImageImport.named_space_for(path)
    var source := named if named != null else SaImageImport.convention_for(path)
    if asks_for(image):
        SaImportFitDialog.choose_depth(host, image, source, done, named != null, SaImageImport.profile_for(path))
        return
    var guessed := source if source != null else SaColorSpace.srgb()
    done.call(guessed.with_depth(SaImportFitDialog.remembered_depth() as SaColorSpace.Depth))


## Whether *image* is one the question is asked about: a float file while the
## question is on, and an eight-bit one only when Preferences asks every time.
static func asks_for(image: Image) -> bool:
    if not SaSettings.ask_when_opening:
        return false
    return SaImageImport.depth_for(image) >= 0 or SaSettings.ask_eight_bit_when_opening
