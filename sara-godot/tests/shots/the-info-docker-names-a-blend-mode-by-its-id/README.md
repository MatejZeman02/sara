# The Info docker scenario's record, and the one shot it does not hold

Three of this scenario's four shots are recorded in each variant folder here,
named after the steps that take them. The fourth, `4-the-info-docker`, is
deliberately not, and `shot_diff.py` therefore never reads it: `pairs` walks the
record folder, so a shot with no picture there is a shot no check compares.
Each variant's `record.json` names it under `"leaves_out"`, so
`check_shots.py --record` leaves it out of a new variant too.

That shot is the only one that carries the Info docker, and two of the docker's
sections hold numbers no two runs share. Its Build section names the commit of
the checkout that ran it, and its GPU section reports the composites' own
timings. Measured on one machine, the scenario run three times on
one checkout: `4-the-info-docker` came back 654, 740 and 267 texels over the
default tolerance of 6, at (1265, 460) and (1290, 465), both of them GPU rows.
Against `b710e4eb` it is 1214 texels over, worst 223 at (1176, 105), which is
the Build section. A picture like that is worse than no record, so it has none
and is a demonstration for a person rather than a check.

The scenario is unchanged in what it proves. Every claim it makes is read from
the state dump its `state` steps write, and the dump reports the Info docker's
rows whether the docker is open or not, because `main.gd` binds the docker's
canvas and tool machine at boot. The Active layer row reads `Normal (sRGB)`,
`sRGB Normal` and `Hard Mix` across the three recorded steps, identically in
all three runs and on both checkouts. The three recorded frames are the canvas
and the Layers docker, taken before the Info docker is placed.
