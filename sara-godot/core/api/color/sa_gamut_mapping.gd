## What happens to a colour on its way out of the float path into a range that
## cannot hold it: the screen, and a file of integer samples.
##
## Two modes, chosen above all for the negative colours a clip cuts. `clip` cuts each channel at the edge of the cube
## on its own, which is what every other program writes and what a painter
## comparing files needs. `oklab` holds lightness and hue and gives up chroma
## until the colour fits, so a saturated colour outside the cube keeps its hue
## instead of turning towards whichever channel was cut. Oklab is the default,
## and the preference is View > Gamut Mapping as well as a Display row, because
## a brightness and contrast pass left negatives that clipped badly on a screen
## whose painter had never opened the Display page.
##
## The mapping never reaches a stored pixel. It is read where a value leaves: the
## view's last step in `shaders/canvas/tonemap.gdshader` and the export's cell
## walk in `SaExportGamut`, which runs `shaders/compute/map_into_gamut.gmacs`. The two
## carry one `gamut_map` body, and `core/api/color/tests/test_the_gamut_mapping_preference.gd`
## fails the run when they drift.
##
## This class is the decision, once. The view's writer and the export both ask
## it, so the two cannot read the preference two ways. It names no setting of its
## own: the caller hands it `SaSettings.gamut_mapping`, because a library under
## `core/api` does not reach for the profile.
##
## A mode is its key rather than a number, the way `import_fit` is, so a third
## mode added later renumbers nothing in a saved profile and an unknown key reads
## as clip, the mapping a file of integer samples gets everywhere else.
@tool
class_name SaGamutMapping
extends RefCounted

const CLIP: String = "clip"
const OKLAB: String = "oklab"

## Every mode, in the order the Preferences row lists them.
const MODES: Array[String] = [CLIP, OKLAB]


## *key* when it names a mode, clip otherwise.
static func normalized(key: String) -> String:
    return key if MODES.has(key) else CLIP


## What the view shader's `gamut_mapping` uniform is written with for *key*:
## the mode's place in [constant MODES], so 0 is clip and leaves the fragment
## as it was.
static func uniform_value(key: String) -> int:
    return MODES.find(normalized(key))


## Whether an export under *key* runs the mapping kernel. *keeps_range* is true
## for a file that holds every float as it stands, EXR and the 32-bit TIFF, and
## such a file is never mapped whatever the preference says: the no-clamp path
## stays bit-exact (hard rule 5).
static func export_maps(key: String, keeps_range: bool) -> bool:
    return not keeps_range and normalized(key) == OKLAB


## The key an export is handed: *key* for a file that narrows, clip for one
## that keeps its range, so a caller passes one value on and asks nothing twice.
static func for_export(key: String, keeps_range: bool) -> String:
    return OKLAB if export_maps(key, keeps_range) else CLIP
