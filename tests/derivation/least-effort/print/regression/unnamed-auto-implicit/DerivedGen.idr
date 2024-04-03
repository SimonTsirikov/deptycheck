module DerivedGen

import AlternativeCore
import PrintDerivation

import Data.Fin

%default total

mutual
  data X : Type where
    Nil  : X
    (::) : (x : Unit) ->
           (xs : X) ->
           Y x xs =>
           X

  data Y : Unit -> X -> Type where
    A : Y n []
    B : Y n xs ->
        Y x xs =>
        Y n (x::xs)

%language ElabReflection

%runElab printDerived @{MainCoreDerivator @{LeastEffort}} $ Fuel -> (f : _) -> Gen MaybeEmpty (u ** Y u f)
