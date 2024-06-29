This folder contains a set of custom formulas you can play with.

Formulas can be loaded directly from the Custom Compute menu or entered from the
command line as "custom:filename".

    y-cruncher custom custom:"filename.cfg"


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

Formulas that are suffixed with a term like (G2) or (G3) means it is a term-wise
expansion of the original formula. Therefore formulas that differ only by this
are the same and cannot be used as compute+verify pairs.


--------------------------------------------------------------------------------

2^(1/5):

Fastest Pair:
    2^(1d5) - Native
    2^(1d5) - Series

The series formula is very slow. Instead, just compute: 200000^(1/5).
The digits will be the same, but shifted over by 1.

--------------------------------------------------------------------------------

2^(1/7):

Fastest Pair:
    2^(1d7) - Native
    2^(1d7) - Series

The series formula is very slow. Instead, just compute: 20000000^(1/7).
The digits will be the same, but shifted over by 1.


--------------------------------------------------------------------------------

Catalan's Constant:

Fastest Pair:
    Catalan - Pilehrood (short)
    Catalan - Zuniga (2023)

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.

Dependent Set:
    Catalan - Huvent (combined)
    Catalan - Huvent (optimized)
    Catalan - Huvent (original)

Dependent Set:
    Catalan - Ramanujan (unoptimized)
    Catalan - Ramanujan

Dependent Set:
    Catalan - Pilehrood (short)
    Catalan - Pilehrood (short G3)

--------------------------------------------------------------------------------

Cbrt(2):

Fastest Pair:
 -  Cbrt(2) - Native
 -  Cbrt(2) - Series2

The series formula is very slow. Instead, just compute: 2000^(1/3).
The digits will be the same, but shifted over by 1.


--------------------------------------------------------------------------------

Cbrt(3):

Fastest Pair:
 -  Cbrt(3) - Native
 -  Cbrt(3) - Series

The series formula is very slow. Instead, just compute: 3000^(1/3).
The digits will be the same, but shifted over by 1.


--------------------------------------------------------------------------------

Cos(1):

Fastest Pair:
    Cos(1) - Series
    Cos(1) - Half Angle Formula


--------------------------------------------------------------------------------

e:

Fastest Pair:
    e - exp(1)
    e - exp(-1)

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.

Dependent Set:
    e^-1 - Native
    e - exp(-1)


--------------------------------------------------------------------------------

Gamma(1/3):

Fastest Pair:
    Gamma(1d3) - Guillera (2023) (G2).cfg
    Gamma(1d3) - Brown (2011).cfg

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.

Dependent Set:
    Gamma(1d3) - Guillera (2023).cfg
    Gamma(1d3) - Zuniga (2024).cfg


--------------------------------------------------------------------------------

Gamma(1/4):

Fastest Pair:
    Gamma(1d4) - Lemniscate Ebisu (2016)
    Gamma(1d4) - Lemniscate Zuniga (2023-x)

Dependent Set:
    Gamma(1d4) - Lemniscate Zuniga (2023-x)
    Gamma(1d4) - Lemniscate Zuniga (2023-viii)
    Gamma(1d4) - AGM-Pi
    Gamma(1d4) - Series-Pi
    Gamma(1d4) - Lemniscate

These 4 formulas have the same relative dependency on Pi. They can only be used
to verify each other if Pi is computing using different algorithms.


--------------------------------------------------------------------------------

Gamma(1/6):

Fastest Pair:
    Gamma(1d6) - Series-Pi
    Gamma(1d6) - AGM-Pi

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
    Gamma(3d4) - AGM-Pi
    Gamma(3d4) - Series-Pi

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Gamma(5/6):

Fastest Pair:
    Gamma(2d3) - Series-Pi
    Gamma(2d3) - AGM-Pi

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Gauss's Constant:

Fastest Pair:
    Gauss - AGM
    Gauss - Series


--------------------------------------------------------------------------------

Golden Ratio:

Fastest Pair:
    GoldenRatio - Native Invsqrt
    GoldenRatio - Series

Note that you really don't want to use the series formula here. The fastest way
to compute+verify is to run the built-in function for this constant and
sqrt(125). The digits will be the same except for the 2nd digit and all the
digits will be shifted over by one.


--------------------------------------------------------------------------------

Lemniscate:

Fastest Pair:
    Lemniscate - Zuniga (2023-x)
    Lemniscate - Guillera

Many of the formulas that use Pi have the same relative dependency on Pi. The
full list of which formulas are dependent has not been enumerated.


--------------------------------------------------------------------------------

Log(2):

Fastest Pair:
    Log(2) - Machin (3 terms)
    Log(2) - Machin (4 terms)

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.


--------------------------------------------------------------------------------

Log(Pi):

Fastest Pair: none

Dependent Set:
    Log(Pi) (unoptimized)
    Log(Pi)


--------------------------------------------------------------------------------

Pi:

Fastest Pair:
    Pi - Chudnovsky
    Pi - Ramanujan

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.


--------------------------------------------------------------------------------

Sin(1):

Fastest Pair:
    Sin(1) - Half Angle Formula
    Sin(1) - Series


--------------------------------------------------------------------------------

Sqrt(2):

Fastest Pair:
    Sqrt(2) - Native Invsqrt
    Sqrt(2) - Series

The series formula is very slow. Instead, just compute: Sqrt(200).
The digits will be the same, but shifted over by 1.


--------------------------------------------------------------------------------

Universal Parabolic Constant:

Fastest Pair: none

Dependent Set:
    Universal Parabolic Constant (unoptimized)
    Universal Parabolic Constant


--------------------------------------------------------------------------------

Zeta(2):

Fastest Pair:
    Zeta(2) - Chudnovsky
    Zeta(2) - Direct

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Zeta(3):

Fastest Pair:
    Zeta(3) - Zuniga (2023-vi)
    Zeta(3) - Zuniga (2023-v)

This constant is supported natively in y-cruncher. So it's faster to use the
built-in implementations instead.

--------------------------------------------------------------------------------

Zeta(4):

Fastest Pair:
    Zeta(4) - Chudnovsky
    Zeta(4) - Direct

These two formulas have the same relative dependency on Pi. Therefore Pi is set
to use two different algorithms.


--------------------------------------------------------------------------------

Zeta(5):

Fastest Pair:
    Zeta(5) - Y.Zhao
    Zeta(5) - BBP-Kruse

Dependent Set:
    Zeta(5) - Broadhurst
    Zeta(5) - Broadhurst (Huvent 2006)
    Zeta(5) - Broadhurst (optimized)





