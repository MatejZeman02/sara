# Changelog

What changed in the noise brush engine, by version. Each release reads the section of the
version the `manifest.cfg` carries, and refuses a release with no such section.

## 1.0.0-alpha.1

The README now says what each field does, gives three starting presets, shows how to write a field as a `.gmacs` file or register one from a module, and carries a picture made in Sara. `Field` is no longer a constant alias of the registry's class, so the module passes the linter, and the first comment of `noise_stretch.gd` says what the file is while the reasoning moved to the README.
A `manifest.cfg` says what the module is and its version, which Sara reads before any of its code, and the versions move with each release from here on.
The module extends `SaModule`, the base class's new name.
A stroke whose pen goes back along its own line, a turn past 162 degrees, keeps each streak on the line it ran out on, where the return used to lay the mirror of the way out and bend each streak round a half circle at the turn.
The outline of a soft noise stroke wanders in long runs, breaks in places and takes nicks of two sizes at no spacing, and the two strands nearest each edge of a bristle field break at lengths of their own, so the edge is no longer one tuft repeated. A hard brush keeps its hard edge.
A pen that comes back over paint the same stroke laid, three tip radii of path or more before, builds it up, so a scrub fills in, where every pass used to wash to the strongest any pass gave. A single pass, a turn and a straight stroke paint what they did.
The strands of a bristle field are no longer alike. Each draws its own width, some wide enough to merge with a neighbour and some a thin line, swells and thins along its run, ends in a point after a length of its own, falls off at an edge from sharp to soft, and paints a little lighter or darker than the colour, moving along its length, with the hue kept.
A pen that rests on its press a moment before it moves opens its stroke at the pressure its first sample reports, where the press used to lay a blot at full pressure in every preset and a press that starts firm still opens dark.
A stroke whose pen presses harder or lighter as it lifts ends at its body's size, where a brush whose size follows the pressure used to end on a dab cut in half, a large half and a small one with a straight cut between them.
Graphite Pencil's grain is a pencil's, specks of 2.5 pixels where they were 4, so at the size the line breaks on the paper's tooth rather than into blotches as wide as itself.
The strands of a bristle field lie at a spacing of their own. Across the brush their cells stand up to 30 percent wider or narrower than the mean, in clumps a stroke draws afresh, so Bristle Flat's hairs no longer lie as an even comb and two strokes lay them in other places. A Spread of nought keeps the even comb.

## 0.19.1

The noise brush as Sara 0.19.1 shipped it, one smooth stroke shaped by a noise texture, the pressure and an image tip.
