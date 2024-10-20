module DerivedGen

import AlternativeCore

import Deriving.DepTyCheck.Gen

%default total

%language ElabReflection

%logging "deptycheck.derive.print" 5
%runElab deriveGenPrinter @{Ext_XSS} $ Fuel -> (Fuel -> Gen MaybeEmpty String) => Gen MaybeEmpty XSS
