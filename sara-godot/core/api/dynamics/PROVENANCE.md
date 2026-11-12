# What the brush's dynamics owe Krita, the two ports in the door

The sensors, the curve option, the dynamics, the dab parameters, the stroke
state and the colour dynamics live in the door, so that any engine reads
pressure and tilt through the same classes a third party's engine would. Two
of the six carry a port of Krita 5.2.13, the stroke state's in the speed
smoother it extends, and their copyright lines sit on this page, beside
[the stamp brush's page](../../../modules/sara-base-modules/stamp-brush/PROVENANCE.md),
which keeps the three ports the module still holds and says why the lines live
on a page rather than in headers.

**Krita 5.2.13 is `GPL-2.0-or-later` throughout the sources below.** That
permits relicensing upwards, and Sara is `GPL-3.0-or-later`, so a port carries
the original lines unmodified beside Sara's own identifier. Both files below
carry `SPDX-License-Identifier: GPL-3.0-or-later` and a pointer to this page.

What was read rather than taken is recorded in the Provenance table of
whose port rows these two are.

## The ports

**Two ports in two files, and no others.** A port added later adds a section
here in the same commit. `tests/test_dynamics_provenance.gd` reads this page
and fails the moment a file under `core` or `ui/brush_editor` carries a line no
section below grants, and the stamp brush's `tests/test_provenance.gd` holds
this page's count and the stamp's together to the spec tables' port rows.

### `res://core/api/dynamics/sa_sensor.gd`

`tilt_elevation`, how upright a pen is from the two lean angles a tablet reports.
Read from `libs/image/brushengine/kis_paint_information.cc`. It is left a port
and says why where it stands: the two angles do not answer the question on their
own, so turning them into one elevation is a tuned choice rather than a
derivation, and every honest derivation answers a different number and moves
every stroke a tilt-elevation curve has ever driven.

```
SPDX-FileCopyrightText: 2007, 2010 Cyrille Berger <cberger@cberger.net>
```

### `res://core/api/dynamics/speed/sa_speed_smoother.gd`

The speed smoother: a backwards walk over the recent samples with two stopping
conditions, and a trimmed rolling mean of the intervals in place of the event
clock. Read from `libs/ui/tool/kis_speed_smoother.cpp`. It is left a port because
the shape and its five constants are one tuned answer, and a rewrite reading as a
derivation would move every stroke driven by speed. It lives in the `speed` folder below
this page, as the class the stroke's sample extends, and its line moved with it.

```
SPDX-FileCopyrightText: 2015 Dmitry Kazakov <dimula73@gmail.com>
```
