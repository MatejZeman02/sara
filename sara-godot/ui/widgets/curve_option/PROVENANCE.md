# What the curve editor owes Krita, the one port in the toolkit

The curve option control and its sensor list were the stamp brush's `ui/`
files until they moved into the widget toolkit, so that any
engine's page, the noise brush's first, draws the curve editor a painter
already knows from the stamp's. The control carries one port of Krita 5.2.13,
and its copyright lines moved here with it from
[the stamp brush's page](../../../modules/sara-base-modules/stamp-brush/PROVENANCE.md),
which keeps the ports the module still holds and says why the lines live on a
page rather than in headers. The sensors and the stroke state the control reads
owe two more, on [the dynamics page](../../../core/api/dynamics/PROVENANCE.md).

**Krita 5.2.13 is `GPL-2.0-or-later` throughout the source below.** That
permits relicensing upwards, and Sara is `GPL-3.0-or-later`, so the port
carries the original lines unmodified beside Sara's own identifier. The file
below carries `SPDX-License-Identifier: GPL-3.0-or-later` and a pointer to this
page.

What was read rather than taken is recorded in the Provenance table of
the Provenance table of the brush dynamics notes,
whose port row this one is. The control's layout is Krita's widget rearranged
for a page, which that table records as an idea and which owes nothing.

## The ports

**One port in one file, and no others.** A port added later adds a section
here in the same commit. `tests/test_dynamics_provenance.gd` reads this page
beside the dynamics page and fails the moment a file under `ui/widgets` carries
a line no section below grants, and the stamp brush's `tests/test_provenance.gd`
holds this page's count, the dynamics page's and the stamp's together to the
spec tables' port rows.

### `res://ui/widgets/curve_option/sa_curve_option_control.gd`

The eight curve preset shapes and their control points, the buttons a painter
presses to get a ramp, an S or an arch. Read from
`plugins/paintops/libpaintop/KisCurveOptionWidget.cpp`. A list of hand-chosen
points rather than a mechanism, so there is nothing to derive: rewriting it
changes what eight buttons do.

```
 * SPDX-FileCopyrightText: 2008 Boudewijn Rempt <boud@valdyas.org>
 * SPDX-FileCopyrightText: 2009 Sven Langkamp <sven.langkamp@gmail.com>
 * SPDX-FileCopyrightText: 2011 Silvio Heinrich <plassy@web.de>
 * SPDX-FileCopyrightText: 2022 Dmitry Kazakov <dimula73@gmail.com>
```

The odd indentation and the leading `*` are Krita's own, kept because the lines
are reproduced verbatim.
