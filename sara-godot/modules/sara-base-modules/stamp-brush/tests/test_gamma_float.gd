## Unit tests for GammaFloat utility class.
extends "res://tests/test_framework.gd"


func test_gamma_float_init() -> void:
    var gf := GammaFloat.new(0.5, 2.0)
    assert_eq(gf.raw(), 0.5, "Raw value should be 0.5")
    assert_eq(gf.gamma(), 2.0, "Gamma should be 2.0")
    assert_eq(gf.gamma_inv(), 0.5, "Inverse gamma should be 0.5")


func test_gamma_float_apply() -> void:
    var gf := GammaFloat.new(0.5, 2.0)
    # 0.5 ^ 2.0 = 0.25
    assert_almost_eq(gf.apply(), 0.25, 0.0001, "Apply should calculate 0.5^2 = 0.25")


func test_gamma_float_apply_inverse() -> void:
    var gf := GammaFloat.new(0.25, 2.0)
    # 0.25 ^ (1/2.0) = 0.5
    assert_almost_eq(gf.apply_inverse(), 0.5, 0.0001, "Apply inverse should calculate sqrt(0.25) = 0.5")


func test_gamma_float_has_same_gamma() -> void:
    var gf1 := GammaFloat.new(0.5, 2.0)
    var gf2 := GammaFloat.new(0.8, 2.0)
    var gf3 := GammaFloat.new(0.5, 1.0)
    assert_true(gf1.has_same_gamma(gf2), "gf1 and gf2 should have same gamma")
    assert_false(gf1.has_same_gamma(gf3), "gf1 and gf3 should have different gamma")
