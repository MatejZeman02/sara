## **The ring's lift out of black**: a hue taken on the ring while the paint is
## black gives a colour the painter can see.
##
## A fresh profile starts with the paint at black, and every shape builds its
## colour from the hue and the two axes it still holds, so a turn of the ring
## at black moved the hue and left the paint black. The newcomer's first hour
## took three tries to land a colour. A gesture on the ring, or on whatever
## turns a shape's hue (the disc's own press, the HSL square's hue bar), that
## starts on a colour darker than [constant FLOOR] starts instead from a mid
## colour of the hue the pointer is on, once, as the gesture starts. A drag of
## the point down to black after it keeps black, and a press in the area
## keeps black as it always did.
##
## A file of its own rather than more of [SaPickerShape], which is near the
## line count where a file is an alarm. This holds the rule and its numbers,
## and the shape asks it at the start of a gesture and reads the colour back
## through its own model, so what the axes mean stays the shape's business.
extends RefCounted

class_name SaRingLift

const OkhslConversionsScript = preload("res://utils/okhsl_conversions.gd")
const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")

## The Oklab lightness under which a ring gesture lifts the colour. Black and
## the near blacks a painter cannot tell a hue in sit under it, and a dark
## navy chosen on purpose sits over it.
const FLOOR: float = 0.1
## The Oklab lightness the lift lands on, the middle of the range, where every
## hue holds a chroma the eye reads as that hue.
const LIGHTNESS: float = 0.6
## How much of the chroma the gamut holds at [constant LIGHTNESS] the lift
## takes, short of the edge so the point lands inside the area.
const CHROMA_SHARE: float = 0.8
## The disc's lift, in its own OKHSL lightness, the toe of [constant LIGHTNESS].
## The disc's press is its hue and saturation, so only the lightness moves.
const DISC_LIGHTNESS: float = 0.58


## Whether *col* is dark enough that a turn of the hue would show nothing.
static func is_dark(col: Color) -> bool:
    return OkhslConversionsScript.srgb_to_oklch(col).z < FLOOR


## The colour a ring gesture at Oklab hue *oklab_hue* starts from when the
## paint is dark: [constant LIGHTNESS] in Oklab and most of the chroma the
## gamut holds there.
static func colour(oklab_hue: float) -> Color:
    var angle := TAU * fposmod(oklab_hue, 1.0)
    var chroma := CHROMA_SHARE * OkhslConversionsScript.gamut_chroma(cos(angle), sin(angle), LIGHTNESS)
    return OkhslConversionsScript.oklch_to_srgb(oklab_hue, chroma, LIGHTNESS)
