## A painter's own sweeps, cleaned and fitted.
##
## Recorded on a slower machine on 2026-11-02 with `sara --trail-input` and charted by
## `sweep_report.py` in the unit's proof folder: three slow sweeps left to
## right and one quick one, each as raw pressure against where the pen was
## along the stroke, 0 at its first event and 1 at its last. The numbers are
## the trail's as written, every event of each stroke, pairs of where along and
## raw pressure, kept as text so seven pairs share a line rather than one
## number taking a line each. No GPU and no pen, since what is under test is
## arithmetic.
extends "res://tests/test_framework.gd"

## The first, 189 events over 1,008 px.
const SLOW_ONE := """
0.0000 0.075  0.0000 0.066  0.0010 0.063  0.0010 0.063  0.0020 0.063  0.0030 0.063  0.0030 0.074
0.0040 0.083  0.0049 0.091  0.0059 0.101  0.0069 0.110  0.0079 0.122  0.0089 0.131  0.0109 0.140
0.0129 0.146  0.0139 0.153  0.0159 0.158  0.0189 0.164  0.0209 0.169  0.0239 0.174  0.0259 0.177
0.0288 0.181  0.0319 0.184  0.0348 0.188  0.0388 0.191  0.0428 0.195  0.0458 0.198  0.0507 0.199
0.0547 0.201  0.0587 0.205  0.0637 0.206  0.0676 0.210  0.0726 0.213  0.0776 0.214  0.0825 0.217
0.0875 0.220  0.0924 0.220  0.0975 0.221  0.1034 0.221  0.1083 0.221  0.1143 0.224  0.1203 0.224
0.1262 0.225  0.1322 0.228  0.1382 0.229  0.1442 0.231  0.1511 0.232  0.1570 0.236  0.1640 0.239
0.1700 0.244  0.1770 0.246  0.1839 0.248  0.1909 0.248  0.1978 0.248  0.2057 0.249  0.2127 0.252
0.2196 0.252  0.2276 0.252  0.2345 0.252  0.2424 0.252  0.2493 0.252  0.2573 0.252  0.2652 0.252
0.2721 0.253  0.2800 0.256  0.2880 0.256  0.2959 0.256  0.3038 0.259  0.3118 0.259  0.3207 0.263
0.3287 0.264  0.3366 0.264  0.3456 0.265  0.3536 0.268  0.3615 0.268  0.3705 0.269  0.3784 0.271
0.3864 0.272  0.3943 0.272  0.4033 0.272  0.4112 0.272  0.4192 0.273  0.4281 0.273  0.4360 0.272
0.4440 0.272  0.4520 0.273  0.4599 0.273  0.4679 0.273  0.4759 0.273  0.4838 0.273  0.4927 0.274
0.5007 0.276  0.5087 0.276  0.5157 0.276  0.5237 0.279  0.5317 0.280  0.5387 0.283  0.5467 0.284
0.5547 0.284  0.5617 0.288  0.5696 0.291  0.5766 0.293  0.5836 0.296  0.5906 0.297  0.5976 0.300
0.6045 0.300  0.6115 0.302  0.6175 0.302  0.6245 0.302  0.6314 0.302  0.6374 0.302  0.6444 0.302
0.6504 0.304  0.6563 0.304  0.6623 0.305  0.6682 0.305  0.6742 0.305  0.6792 0.305  0.6851 0.305
0.6911 0.306  0.6971 0.306  0.7021 0.309  0.7080 0.311  0.7140 0.311  0.7190 0.315  0.7249 0.318
0.7299 0.320  0.7359 0.320  0.7409 0.323  0.7468 0.323  0.7518 0.323  0.7568 0.323  0.7628 0.323
0.7677 0.323  0.7737 0.323  0.7787 0.324  0.7846 0.324  0.7896 0.324  0.7945 0.324  0.7995 0.324
0.8045 0.325  0.8094 0.327  0.8144 0.327  0.8193 0.327  0.8243 0.328  0.8293 0.328  0.8343 0.329
0.8392 0.332  0.8442 0.332  0.8501 0.333  0.8550 0.336  0.8600 0.337  0.8649 0.337  0.8699 0.337
0.8748 0.340  0.8798 0.340  0.8838 0.340  0.8888 0.341  0.8937 0.341  0.8977 0.342  0.9026 0.342
0.9076 0.342  0.9115 0.342  0.9165 0.342  0.9214 0.342  0.9254 0.342  0.9293 0.342  0.9343 0.341
0.9383 0.341  0.9413 0.341  0.9452 0.341  0.9492 0.341  0.9522 0.341  0.9561 0.342  0.9601 0.342
0.9631 0.342  0.9660 0.342  0.9700 0.342  0.9730 0.342  0.9770 0.340  0.9799 0.329  0.9830 0.310
0.9859 0.287  0.9890 0.260  0.9920 0.225  0.9950 0.178  0.9970 0.116  0.9990 0.054  1.0000 0.001
"""

## The second, 166 events over 919 px.
const SLOW_TWO := """
0.0000 0.044  0.0000 0.044  0.0011 0.042  0.0011 0.040  0.0022 0.040  0.0022 0.044  0.0032 0.055
0.0043 0.070  0.0054 0.088  0.0076 0.102  0.0087 0.118  0.0108 0.130  0.0130 0.143  0.0152 0.157
0.0173 0.169  0.0206 0.180  0.0239 0.191  0.0271 0.201  0.0304 0.208  0.0347 0.214  0.0380 0.221
0.0434 0.228  0.0478 0.237  0.0521 0.245  0.0576 0.255  0.0630 0.261  0.0685 0.268  0.0739 0.275
0.0793 0.281  0.0848 0.288  0.0913 0.293  0.0979 0.298  0.1044 0.302  0.1120 0.306  0.1185 0.310
0.1262 0.315  0.1338 0.315  0.1403 0.316  0.1479 0.318  0.1555 0.319  0.1631 0.320  0.1718 0.323
0.1795 0.323  0.1871 0.323  0.1958 0.327  0.2045 0.331  0.2132 0.332  0.2208 0.332  0.2295 0.333
0.2382 0.336  0.2470 0.340  0.2557 0.341  0.2644 0.341  0.2731 0.345  0.2829 0.349  0.2916 0.349
0.3003 0.350  0.3090 0.354  0.3177 0.358  0.3264 0.359  0.3351 0.363  0.3438 0.364  0.3525 0.368
0.3612 0.372  0.3699 0.372  0.3775 0.373  0.3862 0.374  0.3949 0.374  0.4026 0.374  0.4113 0.377
0.4200 0.378  0.4287 0.379  0.4374 0.381  0.4450 0.382  0.4537 0.382  0.4624 0.386  0.4711 0.386
0.4787 0.387  0.4875 0.390  0.4962 0.391  0.5038 0.391  0.5125 0.394  0.5212 0.394  0.5288 0.395
0.5364 0.396  0.5440 0.401  0.5527 0.402  0.5604 0.404  0.5680 0.405  0.5767 0.406  0.5843 0.410
0.5919 0.413  0.6006 0.413  0.6083 0.415  0.6159 0.417  0.6235 0.418  0.6311 0.419  0.6387 0.419
0.6463 0.419  0.6540 0.419  0.6627 0.419  0.6692 0.424  0.6768 0.424  0.6844 0.424  0.6921 0.424
0.6986 0.425  0.7051 0.425  0.7127 0.425  0.7193 0.429  0.7269 0.429  0.7334 0.429  0.7410 0.429
0.7476 0.429  0.7541 0.429  0.7617 0.429  0.7682 0.429  0.7748 0.429  0.7813 0.430  0.7878 0.430
0.7944 0.430  0.7998 0.430  0.8063 0.430  0.8129 0.430  0.8194 0.430  0.8259 0.433  0.8325 0.433
0.8379 0.433  0.8444 0.433  0.8499 0.433  0.8553 0.433  0.8607 0.433  0.8662 0.433  0.8716 0.433
0.8781 0.433  0.8836 0.433  0.8890 0.432  0.8945 0.432  0.8999 0.433  0.9053 0.434  0.9097 0.434
0.9151 0.434  0.9206 0.433  0.9249 0.433  0.9293 0.433  0.9347 0.433  0.9391 0.433  0.9434 0.433
0.9478 0.433  0.9521 0.433  0.9565 0.433  0.9608 0.433  0.9641 0.432  0.9684 0.432  0.9717 0.432
0.9761 0.428  0.9793 0.419  0.9826 0.409  0.9858 0.392  0.9880 0.372  0.9913 0.341  0.9935 0.305
0.9956 0.259  0.9967 0.196  0.9978 0.120  1.0000 0.046  1.0000 0.001
"""

## The third, 180 events over 873 px.
const SLOW_THREE := """
0.0000 0.061  0.0000 0.077  0.0000 0.083  0.0000 0.083  0.0000 0.083  0.0000 0.086  0.0000 0.091
-0.0000 0.100  0.0011 0.110  0.0011 0.122  0.0023 0.131  0.0023 0.138  0.0034 0.143  0.0034 0.147
0.0046 0.153  0.0057 0.159  0.0069 0.164  0.0091 0.170  0.0103 0.177  0.0126 0.183  0.0149 0.188
0.0172 0.195  0.0195 0.198  0.0217 0.201  0.0252 0.205  0.0286 0.209  0.0321 0.213  0.0355 0.218
0.0389 0.221  0.0435 0.224  0.0481 0.225  0.0515 0.228  0.0561 0.231  0.0607 0.232  0.0653 0.235
0.0710 0.237  0.0756 0.240  0.0813 0.245  0.0870 0.248  0.0927 0.255  0.0996 0.260  0.1053 0.265
0.1122 0.269  0.1191 0.275  0.1260 0.277  0.1328 0.280  0.1397 0.283  0.1477 0.285  0.1546 0.287
0.1626 0.288  0.1706 0.289  0.1786 0.293  0.1867 0.296  0.1958 0.297  0.2038 0.297  0.2130 0.301
0.2210 0.302  0.2302 0.305  0.2393 0.306  0.2474 0.306  0.2565 0.307  0.2668 0.310  0.2760 0.311
0.2852 0.313  0.2943 0.314  0.3046 0.316  0.3138 0.319  0.3230 0.320  0.3333 0.320  0.3425 0.323
0.3528 0.327  0.3619 0.331  0.3722 0.332  0.3814 0.333  0.3906 0.336  0.3997 0.337  0.4100 0.340
0.4192 0.341  0.4284 0.345  0.4386 0.347  0.4478 0.353  0.4570 0.353  0.4673 0.355  0.4764 0.358
0.4856 0.359  0.4948 0.360  0.5039 0.363  0.5131 0.364  0.5222 0.367  0.5314 0.369  0.5417 0.369
0.5497 0.369  0.5589 0.372  0.5681 0.372  0.5772 0.373  0.5864 0.374  0.5956 0.374  0.6047 0.377
0.6128 0.379  0.6219 0.379  0.6311 0.381  0.6391 0.381  0.6483 0.382  0.6563 0.383  0.6643 0.383
0.6735 0.385  0.6815 0.387  0.6895 0.390  0.6987 0.390  0.7067 0.390  0.7136 0.391  0.7216 0.392
0.7297 0.392  0.7365 0.392  0.7434 0.392  0.7514 0.394  0.7583 0.395  0.7652 0.396  0.7721 0.400
0.7789 0.400  0.7847 0.400  0.7915 0.400  0.7973 0.400  0.8030 0.400  0.8087 0.402  0.8144 0.402
0.8190 0.405  0.8248 0.405  0.8305 0.405  0.8351 0.408  0.8408 0.408  0.8454 0.409  0.8500 0.410
0.8545 0.410  0.8591 0.413  0.8637 0.414  0.8683 0.414  0.8717 0.414  0.8763 0.414  0.8797 0.414
0.8843 0.414  0.8877 0.414  0.8923 0.414  0.8957 0.414  0.8992 0.414  0.9038 0.414  0.9072 0.414
0.9106 0.414  0.9152 0.414  0.9187 0.415  0.9232 0.415  0.9267 0.415  0.9301 0.415  0.9347 0.415
0.9382 0.416  0.9416 0.418  0.9462 0.418  0.9496 0.418  0.9531 0.418  0.9565 0.417  0.9599 0.416
0.9622 0.416  0.9657 0.415  0.9691 0.414  0.9714 0.410  0.9748 0.401  0.9771 0.391  0.9794 0.379
0.9817 0.368  0.9840 0.350  0.9851 0.334  0.9874 0.314  0.9897 0.292  0.9909 0.269  0.9931 0.244
0.9943 0.204  0.9954 0.150  0.9977 0.088  0.9989 0.023  1.0000 0.001
"""

## The first of the three quick ones, 34 events over 460 px, which peaked at 0.52.
const QUICK := """
0.0000 0.137  0.0022 0.141  0.0043 0.141  0.0065 0.141  0.0130 0.141  0.0196 0.141  0.0283 0.154
0.0413 0.171  0.0543 0.191  0.0696 0.205  0.0870 0.220  0.1065 0.232  0.1283 0.246  0.1522 0.257
0.1783 0.269  0.2065 0.280  0.2370 0.289  0.2717 0.302  0.3065 0.315  0.3457 0.328  0.3848 0.337
0.4283 0.345  0.4717 0.347  0.5174 0.350  0.5652 0.350  0.6130 0.350  0.6609 0.350  0.7109 0.341
0.7609 0.318  0.8109 0.289  0.8587 0.257  0.9065 0.201  0.9543 0.099  1.0000 0.005
"""

## Where each slow sweep's lift was cut, read off the chart: the last reading
## within 2% of the peak, the index and how far along the stroke it is.
const CUTS: Array = [[179, 0.977], [154, 0.9761], [164, 0.9714]]


func _sweep(numbers: String) -> PackedVector2Array:
    var sweep := PackedVector2Array()
    var read := numbers.replace("\n", " ").split_floats(" ", false)
    for i in range(0, read.size(), 2):
        sweep.append(Vector2(read[i], read[i + 1]))
    return sweep


func _slow() -> Array:
    return [_sweep(SLOW_ONE), _sweep(SLOW_TWO), _sweep(SLOW_THREE)]


func _peak(sweep: PackedVector2Array) -> float:
    var peak := 0.0
    for point in sweep:
        peak = maxf(peak, point.y)
    return peak


## Each slow sweep is cut where its pen began to lift, in the last 3% of the
## stroke, and what is left is stretched to fill the block from 0 to 1.
func test_each_slow_sweep_is_cut_where_its_lift_begins() -> void:
    var sweeps := _slow()
    for index in range(3):
        var sweep: PackedVector2Array = sweeps[index]
        var cut: Array = CUTS[index]
        var last := SaTabletSweep.lift_index(sweep)
        assert_eq(last, int(cut[0]), "Sweep %d is cut at event %d" % [index + 1, int(cut[0])])
        assert_almost_eq(sweep[last].x, float(cut[1]), 1e-4, "which is %.3f along it" % float(cut[1]))
        assert_true(sweep[last].x > 0.97, "inside the stroke's last 3%")
        for after in range(last + 1, sweep.size()):
            assert_true(sweep[after].y < _peak(sweep) * SaTabletSweep.LIFT_SHARE, "and nothing after the cut is the peak")
        assert_true(sweep[sweep.size() - 1].y < 0.01, "which falls to nought")

        var cleaned := SaTabletSweep.clean(sweep)
        assert_eq(cleaned.size(), last + 1, "The lift is gone from the cleaned sweep")
        assert_eq(cleaned[0], Vector2(0.0, sweep[0].y), "which keeps the first reading where the pen landed")
        assert_almost_eq(cleaned[cleaned.size() - 1].x, 1.0, 1e-5, "and reaches the far end")
        var previous := -1.0
        for point in cleaned:
            assert_true(point.x >= previous, "with the places never falling")
            previous = point.x


## The slow sweeps count, and the quick one, which peaked halfway and lifted
## while it still moved, does not.
func test_the_slow_sweeps_count_and_the_quick_one_is_refused() -> void:
    for sweep: PackedVector2Array in _slow():
        assert_eq(SaTabletSweep.refusal_of(sweep), SaTabletSweep.Refusal.NONE, "A slow sweep counts")
    var quick := _sweep(QUICK)
    assert_eq(SaTabletSweep.refusal_of(quick), SaTabletSweep.Refusal.EARLY_PEAK, "The quick one peaked too early")
    var reversed := PackedVector2Array()
    for point in _sweep(SLOW_ONE):
        reversed.append(Vector2(1.0 - point.x, point.y))
    assert_eq(SaTabletSweep.refusal_of(reversed), SaTabletSweep.Refusal.FAR_END, "One from the far end is refused")
    var short := PackedVector2Array()
    for point in _sweep(SLOW_ONE):
        short.append(Vector2(point.x * 0.8, point.y))
    assert_eq(SaTabletSweep.refusal_of(short), SaTabletSweep.Refusal.SHORT, "and so is one that stops short")
    var with_the_quick := _slow()
    with_the_quick[2] = quick
    var two := SaTabletSweep.correction_of(with_the_quick)
    var three := SaTabletSweep.correction_of(_slow())
    assert_true(two != three, "A refused sweep is left out of the fit")


## The hardest peak of the three is 0.8, the room above it runs evenly to one
## at the peak over 0.8, and anything harder is full.
func test_the_peak_is_eight_tenths_with_room_above_it() -> void:
    var table := SaTabletSweep.correction_of(_slow())
    assert_eq(table.size(), SaTabletSweep.SAMPLES, "One entry a step")
    var peak := 0.434
    var ceiling := peak / SaTabletSweep.SWEEP_PEAK
    assert_almost_eq(SaTablet.correct(peak, table), 0.8, 0.015, "The hardest peak, raw 0.434, is 0.8")
    assert_almost_eq(SaTablet.correct((peak + ceiling) * 0.5, table), 0.9, 0.015, "halfway up the room is 0.9")
    assert_almost_eq(SaTablet.correct(ceiling, table), 1.0, 0.015, "the peak over 0.8 is full")
    assert_eq(SaTablet.correct(0.9, table), 1.0, "and so is anything harder")
    var previous := -1.0
    for value in table:
        assert_true(value >= previous, "The correction never falls")
        previous = value
    assert_true(SaTablet.correct(0.3, table) < 0.8, "The hand's middle is under the peak")
    assert_true(SaTablet.correct(0.3, table) > SaTabletSweep.FLOOR, "and over the floor")


## Under the softest first reading, raw 0.044, the table rises evenly from
## nought to the floor, so the lightest touch-down lays a faint trace.
func test_the_lightest_touch_down_lays_the_floor() -> void:
    var table := SaTabletSweep.correction_of(_slow())
    assert_eq(table[0], 0.0, "Nothing is still nothing")
    assert_almost_eq(SaTablet.correct(0.044, table), SaTabletSweep.FLOOR, 0.006, "The softest landing is the floor")
    assert_almost_eq(SaTablet.correct(0.022, table), SaTabletSweep.FLOOR * 0.5, 0.006, "and half of it half the floor")
    assert_almost_eq(SaTabletSweep.FLOOR, 0.05, 1e-6, "The floor is 0.05")
