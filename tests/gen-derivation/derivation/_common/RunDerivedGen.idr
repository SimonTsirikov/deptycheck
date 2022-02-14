module RunDerivedGen

import public Generics.Derive

import public Test.DepTyCheck.Gen.Auto

%default total

export %hint
smallStrs : Fuel -> Gen String
smallStrs _ = choiceMap pure ["", "a", "bc"]

export %hint
smallNats : Fuel -> Gen Nat
smallNats _ = choiceMap pure [0, 10]

export
aVect : Fuel -> (Fuel -> Gen a) => (n : Nat) -> Gen (Vect n a)
aVect f Z             = [| [] |]
aVect f (S n) @{genA} = [| genA f :: aVect f n @{genA} |]

export %hint
someTypes : Fuel -> Gen Type
someTypes _ = choiceMap pure [Nat, String, Bool]

export
Show (a = b) where
  show Refl = "Refl"

public export
data GenForRun : Type where
  G : Show x => (Fuel -> Gen x) -> GenForRun

export
runGs : List GenForRun -> IO Unit
runGs checkedGens = do
  putStrLn "Generated values:"
  let genedValues = checkedGens <&> \(G gen) => map show $ take 10 $ evalState someStdGen $ unGen $ gen $ limit 20
  let delim = (putStrLn "-----" >>)
  for_ genedValues $ delim . traverse_ (delim . putStrLn)

export %hint
UsedConstructorDerivator : ConstructorDerivator
UsedConstructorDerivator = LeastEffort