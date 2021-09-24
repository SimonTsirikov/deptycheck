module DerivedGen

import AlternativeCore

import Data.Vect

%default total

%language ElabReflection

%runElab printDerived @{Empty} $ Fuel -> Gen (n : Nat ** a : Type ** Vect n a)
