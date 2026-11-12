# What the stamp brush took from Krita

One file of this module is a port of Krita code, and this page holds its
copyright lines. The rest of the module was written from what Krita's
mechanisms do, and a mechanism that was only read owes nobody a line.

The code was read against the Krita 5.2.13 release sources, which are
`GPL-2.0-or-later`. Sara is `GPL-3.0-or-later`, which that licence permits, so
a port keeps the original copyright lines unmodified beside Sara's own licence
identifier.

## The port

**One port in one file, and no others.** A port added later adds a section here
in the same commit.

### `res://modules/sara-base-modules/stamp-brush/shaders/pattern_modes.gmacs`

The alpha arithmetic of three texture modes, colour burn, hard mix softer and
linear height, so a preset naming one paints the stroke Krita paints. It is read
from `libs/ui/tool/strokes/KisMaskingBrushCompositeOp.h` (`colorBurnAlpha`,
`hardMixSofterPhotoshopAlpha` and the linear height function). They carry
Krita's tuned constants, the three and two of hard mix softer and the 0.99 of
linear height, and a rewrite from what they do would paint a different stroke.

```
SPDX-FileCopyrightText: 2017 Dmitry Kazakov <dimula73@gmail.com>
SPDX-FileCopyrightText: 2021 Deif Lou <ginoba@gmail.com>
```

## Ports that live elsewhere

Three other mechanisms were once part of this module and moved with the code
that owns them. Their lines are on the pages beside that code:

- The tilt elevation and the speed smoother, in
  [`core/api/dynamics/PROVENANCE.md`](https://github.com/MatejZeman02/sara/blob/main/sara-godot/core/api/dynamics/PROVENANCE.md).
- The greyscale mask rule, in
  [`core/api/tip/PROVENANCE.md`](https://github.com/MatejZeman02/sara/blob/main/sara-godot/core/api/tip/PROVENANCE.md).
- The eight curve preset shapes, in
  [`ui/widgets/curve_option/PROVENANCE.md`](https://github.com/MatejZeman02/sara/blob/main/sara-godot/ui/widgets/curve_option/PROVENANCE.md).

## What is deliberately not here

`shaders/compute/libs/erf.gmacs` (in the main repository) is Abramowitz and
Stegun 7.1.26, a work of the United States government and in the public domain.
Krita takes `erf` from `<cmath>` or Boost and implements none, so no line is
owed.

`libs/pigment/compositeops/KoCompositeOpAlphaDarken.h` and
`plugins/paintops/libpaintop/kis_texture_option.cpp` are `LGPL-2.0-or-later`
rather than GPL. Both were only read, so neither owes a line, and the
difference is written down because the day one becomes a port it changes what
has to be said.
