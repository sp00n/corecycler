This folder contains a set of custom formulas you can play with.

Formulas can be loaded directly from the Custom Compute menu or entered from the
command line as "custom:filename".

    y-cruncher custom custom:"constant - algorithm"


More formulas can be found here on the official GitHub repo:

    https://github.com/Mysticial/y-cruncher-Formulas


Documentation for writing custom formulas can be found here:

    http://www.numberworld.org/y-cruncher/guides/custom_formulas.html


--------------------------------------------------------------------------------

The rest of this file documents which pairs of formulas are approved for
compute/verify pairs for the purpose of setting a world record or simply having
verified digits.

Legend:

    "Fastest Pair" indicates the fastest approved pair for formulas.

    "Dependent Set" indicates a set of similar formula. You cannot do a
    compute/verify pair with 2 formulas in the same dependent set.


The term "same relative dependency" will be used several times here. This means
that two formulas are dependent on the same constant in such a way that if the
constant were changed, both formulas will evaluate to the same (incorrect) value.

Formula pairs that fall into these category will use different algorithms for
that constant and are rearranged in a way to avoid any computational dependencies.


--------------------------------------------------------------------------------

2^(1/5):

Fastest Pair:
    2^(1d5) - Native.cfg
    2^(1d5) - Series.cfg

The series formula is very slow. Instead, just compute: 200000^(1/5).
The digits will be the same, but shifted over by 1.

--------------------------------------------------------------------------------

2^(1/7):

Fastest Pair:
    2^(1d7) - Native.cfg
    2^(1d7) - Series.cfg

The series formula is very slow. Instead, just compute: 20000000^(1/7).
The digits will be the same, but shifted over by 1.


--------------------------------------------------------------------------------

Catalan's Constant:

Fastest Pair:
    Catalan - Pilehrood (short).cfg
    Catalan - Guillera (2019).cfg

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.

Dependent Set:
    Catalan - Huvent (combined).cfg
    Catalan - Huvent (optimized).cfg
    Catalan - Huvent (original).cfg

Dependent Set:
    Catalan - Ramanujan (unoptimized).cfg
    Catalan - Ramanujan.cfg


--------------------------------------------------------------------------------

Cbrt(2):

Fastest Pair:
 -  Cbrt(2) - Native.cfg
 -  Cbrt(2) - Series2.cfg

The series formula is very slow. Instead, just compute: 2000^(1/3).
The digits will be the same, but shifted over by 1.


--------------------------------------------------------------------------------

Cbrt(3):

Fastest Pair:
 -  Cbrt(3) - Native.cfg
 -  Cbrt(3) - Series.cfg

The series formula is very slow. Instead, just compute: 3000^(1/3).
The digits will be the same, but shifted over by 1.


--------------------------------------------------------------------------------

Cos(1):

Fastest Pair:
    Cos(1) - Series.cfg
    Cos(1) - Half Angle Formula.cfg


--------------------------------------------------------------------------------

e:

Fastest Pair:
    e - exp(1).cfg
    e - exp(-1).cfg

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.

Dependent Set:
    e^-1 - Native.cfg
    e - exp(-1).cfg


--------------------------------------------------------------------------------

Gamma(1/3):

Fastest Pair:
    Gamma(1d3) - Series-Pi
    Gamma(1d3) - AGM-Pi

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Gamma(1/4):

Fastest Pair:
    Gamma(1d4) - AGM-Pi.cfg
    Gamma(1d4) - Series-Pi.cfg

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Gamma(1/6):

Fastest Pair:
    Gamma(1d6) - Series-Pi.cfg
    Gamma(1d6) - AGM-Pi.cfg

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Gamma(2/3):

Fastest Pair:
    Gamma(2d3) - Series-Pi
    Gamma(2d3) - AGM-Pi

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Gamma(3/4):

Fastest Pair:
    Gamma(3d4) - AGM-Pi.cfg
    Gamma(3d4) - Series-Pi.cfg

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Gamma(5/6):

Fastest Pair:
    Gamma(2d3) - Series-Pi.cfg
    Gamma(2d3) - AGM-Pi.cfg

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Gauss's Constant:

Fastest Pair:
    Gauss - AGM.cfg
    Gauss - Series.cfg


--------------------------------------------------------------------------------

Golden Ratio:

Fastest Pair:
    GoldenRatio - Native Invsqrt.cfg
    GoldenRatio - Series.cfg

Note that you really don't want to use the series formula here. The fastest way
to compute+verify is to run the built-in function for this constant and
sqrt(125). The digits will be the same except for the 2nd digit and all the
digits will be shifted over by one.


--------------------------------------------------------------------------------

Lemniscate:

Fastest Pair:
    Lemniscate - AGM-Pi.cfg
    Lemniscate - Series-Pi.cfg

This is a built-in constant. But the 2nd formula here (Series-Pi) is actually
faster than both the built-in ArcSinlemn formulas.

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Log(2):

Fastest Pair:
    Log(2) - Machin (3 terms).cfg
    Log(2) - Machin (4 terms).cfg

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.


--------------------------------------------------------------------------------

Log(Pi):

Fastest Pair: none

Dependent Set:
    Log(Pi) (unoptimized).cfg
    Log(Pi).cfg


--------------------------------------------------------------------------------

Pi:

Fastest Pair:
    Pi - Chudnovsky.cfg
    Pi - Ramanujan.cfg

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.


--------------------------------------------------------------------------------

Sin(1):

Fastest Pair:
    Sin(1) - Half Angle Formula.cfg
    Sin(1) - Series.cfg


--------------------------------------------------------------------------------

Sqrt(2):

Fastest Pair:
    Sqrt(2) - Native Invsqrt.cfg
    Sqrt(2) - Series.cfg

The series formula is very slow. Instead, just compute: Sqrt(200).
The digits will be the same, but shifted over by 1.


--------------------------------------------------------------------------------

Universal Parabolic Constant:

Fastest Pair: none

Dependent Set:
    Universal Parabolic Constant (unoptimized).cfg
    Universal Parabolic Constant.cfg


--------------------------------------------------------------------------------

Zeta(2):

Fastest Pair:
    Zeta(2) - Chudnovsky.cfg
    Zeta(2) - Direct.cfg

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Zeta(3):

Fastest Pair:
    Zeta(3) - Wedeniwski.cfg
    Zeta(3) - Amdeberhan-Zeilberger.cfg

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.


--------------------------------------------------------------------------------

Zeta(4):

Fastest Pair:
    Zeta(4) - Chudnovsky.cfg
    Zeta(4) - Direct.cfg

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Zeta(5):

Fastest Pair:
    Zeta(5) - BBP-Kruse.cfg
    Zeta(5) - Broadhurst (optimized).cfg

Dependent Set:
    Zeta(5) - Broadhurst.cfg
    Zeta(5) - Broadhurst (Huvent 2006).cfg
    Zeta(5) - Broadhurst (optimized).cfg





