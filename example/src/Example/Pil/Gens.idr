module Example.Pil.Gens

import Data.DPair
import Data.List.Lazier
import public Data.Fuel

import Decidable.Equality

import public Example.Pil.Lang

import public Test.DepTyCheck.Gen

import Syntax.WithProof

%default total

------------------
--- Generation ---
------------------

--- Universal patterns (particular cases) ---

asp : {0 indexed : index -> Type} ->
      {0 fin : {0 idx : index} -> indexed idx -> Type} ->
      Gen (n ** indexed n) ->
      ({0 idx : index} -> {p : indexed idx} -> Gen $ fin p) ->
      Gen (n : index ** p : indexed n ** fin p)
asp rl lr = do (n ** i) <- rl
               pure (n ** i ** !lr)

--- Common ---

lookupGen : (vars : Variables) -> Gen (n : Name ** Lookup n vars)
lookupGen vars = uniform $ fromList $ mapLk vars where
  mapLk : (vars : Variables) -> List (n ** Lookup n vars)
  mapLk []            = []
  mapLk ((n, ty)::xs) = (n ** Here ty) :: map (\(n ** lk) => (n ** There lk)) (mapLk xs)

--- Expressions ---

export
varExprGen : {a : Type'} -> {vars : Variables} -> {regs : Registers rc} -> Gen $ Expression vars regs a
varExprGen = do Element (n ** _) prf <- lookupGen vars `suchThat_invertedEq` a $ \(_ ** lk) => reveal lk
                pure rewrite prf in V n

||| Generator of non-recursive expressions (thus those that can be used with zero recursion bound).
nonRec_exprGen : {a : Type'} -> {vars : Variables} -> {regs : Registers rc} -> Gen (idrTypeOf a) -> Gen $ Expression vars regs a
nonRec_exprGen g = [| C g |] <|> varExprGen
                   -- TODO to add the register access expression

export
exprGen : (fuel : Fuel) ->
          {a : Type'} ->
          ({b : Type'} -> Gen $ idrTypeOf b) ->
          {vars : Variables} ->
          {regs : Registers rc} ->
          ((subGen : {x : Type'} -> Gen $ Expression vars regs x) -> {b : Type'} -> Gen $ Expression vars regs b) ->
          Gen (Expression vars regs a)
exprGen Dry      g _   = nonRec_exprGen g
exprGen (More f) g rec = nonRec_exprGen g <|> rec (exprGen f g rec)

--- General methodology of writing autogenerated-like generators ---

  -- Determine the desired (root) data component and its type parameters.
  -- Say, it is a `X (a : A) (c : C)`.
  -- Determine which parameters finally would be user-defined and which are generated.
  -- Say, `a` is user-defined and `c` is generated.
  -- Then the type of the main generator would be `(a : A) -> Gen (c : C ** X a c)`.

  -- Determine also the types which has external generators and add their `Gen Y =>` to the final signature.
  -- If the type of external generator has the parameter, add it as an implicit one,
  -- e.g. `({u : U} -> Gen (Z u)) =>`.

  -- Do the same if user-defined parameters also have their parameters.
  -- Note, that these parameters can be also used in the type of generated parameters,
  -- so it may start to look like this:
  -- `Gen Y => ({u : U} -> Gen (Z u)) => {w : W} -> (a : A) -> (b : B w) -> Gen (c : C ** d : D w ** X a b c d)`
  -- Let's call this type as `X_c_d_Gen`.
  -- It generates an instance of `X` with some `c` and `d` parameters being given `a` and `b` set.

  -- To control recustion, we should also have a `Fuel` parameter in the type `X_c_d_Gen`.
  -- This is needed because the current `Test.DepTyCheck.Gen` supports only finite generators.

  -- Create a namespace `Xs_given_a_b` at the module level.
  -- All function definitions and implementations now go into that module as long as we stick to generators of type `X_c_d_Gen`.

  -- For each constructor of the desired type (`X` in the example) create a function signature with no arguments of type `X_c_d_Gen`.
  -- Then create an exported function `x_gen` of the same type `X_c_d_Gen`.
  -- Matching on the `Fuel` argument, when `Dry`, it should be `oneOf` with a list of all non-recursive generator functions for constructors
  -- from above as an argument.
  -- For `More f` `Fuel` argument, implementation should be `oneOf` with a list of all generator functions for constructors.

  -- Implementations of all functions should be after all definitions of all generator types.
  -- This is requires for potential mutual recursion

  -- For every generator function for a constructor, determine the constructor's arguments.
  --
  --   There is a need to determine the order of generation for dependently typed parameters.
  --   Sometimes we can generate the left argument and then determine the type of the right (dependent) argument and
  --   generate it then.
  --   In some other cases, we may want to generate the dependent pair as a whole and then use parts of the pair as arguments.
  --   There is not (yet?) a universal decision procedure to determine whether left-to-right or right-to-left method should be applied.
  --
  -- For every argument we need to determine whether the type of argument depends on the user-defined parameters of the generator
  -- that we are currently implementing.
  -- If so, we need appropriate `x_gen` function passing all relevant user-defined arguments.
  --
  --   If there is not such a generator, then the whole generation process should be repeated for this type from the beginning on this methodology.
  --
  -- For external data generators, we use `@{expr}` pattern matching and explicit `!expr` expression to call the generator.
  -- For non-external data generators, we use the `do`-notation and generate appropriate value (or dependent pair of values)
  -- and then use them for generation.
  --
  -- When we are producing the dependent pair, `pure (_ ** _ ** <main_generation_expression>)` should be used as the last generation
  -- expression in the `do`-block.

  -- TODO to automate all this as an elaboration script.

--- Statements ---

public export
0 SpecGen : (Nat -> Type) -> Type
SpecGen res =
  (fuel : Fuel) ->
  {rc : Nat} ->
  Gen Type' =>
  Gen Name =>
  ({ty : Type'} -> {vars : Variables} -> {regs : Registers rc} -> Gen (Expression vars regs ty)) =>
  res rc

namespace Equal_registers

  public export
  0 EqRegisters_Gen : Type
  EqRegisters_Gen = SpecGen \rc => (regs : Registers rc) -> Gen (regs' ** regs' =%= regs)

  refl  : EqRegisters_Gen

  merge_idemp  : EqRegisters_Gen
  merge_comm   : EqRegisters_Gen
  merge_assoc  : EqRegisters_Gen
  merge_assoc' : EqRegisters_Gen

  squashed : EqRegisters_Gen

  withed : EqRegisters_Gen

  export
  eq_registers_gen : EqRegisters_Gen
  eq_registers_gen f regs = oneOf
    [ refl         f regs
    , merge_idemp  f regs
    , merge_comm   f regs
    , merge_assoc  f regs
    , merge_assoc' f regs
    , squashed     f regs
    , withed       f regs
    ]

namespace Equal_registers -- implementations

  refl _ regs = pure (_ ** index_equiv_refl)

  merge_idemp _ regs = pure (_ ** merge_idempotent)

  merge_comm _ $ r1 `Merge` r2 = pure (_ ** merge_commutative)
  merge_comm _ _ = empty

  merge_assoc _ $ a `Merge` (b `Merge` c) = pure (_ ** merge_associative)
  merge_assoc _ _ = empty

  merge_assoc' _ $ (a `Merge` b) `Merge` c = pure (_ ** index_equiv_sym merge_associative)
  merge_assoc' _ _ = empty

  squashed _ $ Base _ = empty -- just to not to repeat `refl` since squash of `Base` is the same
  squashed _ _ = pure (_ ** squashed_regs_equiv)

  withed _ _ = case rc of
    Z   => empty -- no such generator if there are no registers, sorry.
    S _ => pure (_ ** withed_with_same_equiv {j = !chooseAny})

  -- TODO to think of reverse `squashed` and `withed`, i.e. those which
  --   - by a `rs@(Base xs)` generates those that squash to `rs` and
  --   - by a `rs `With` (i, index i rs)` returns `rs`.

  -- TODO to think of recusrive application of these generators.

namespace Statements_given_preV_preR_postV_postR

  public export
  0 Statement_no_Gen : Type
  Statement_no_Gen = SpecGen \rc => (preV : Variables) -> (preR : Registers rc) -> (postV : Variables) -> (postR : Registers rc) ->
                                    Gen (Statement preV preR postV postR)

  nop_gen   : Statement_no_Gen
  dot_gen   : Statement_no_Gen
  v_ass_gen : Statement_no_Gen
  for_gen   : Statement_no_Gen
  if_gen    : Statement_no_Gen
  seq_gen   : Statement_no_Gen
  block_gen : Statement_no_Gen
  print_gen : Statement_no_Gen

  export
  statement_gen : Statement_no_Gen
  statement_gen Dry preV preR postV postR = oneOf
    [ nop_gen   Dry preV preR postV postR
    , dot_gen   Dry preV preR postV postR
    , v_ass_gen Dry preV preR postV postR
    , print_gen Dry preV preR postV postR
    ]
  statement_gen (More f) preV preR postV postR = oneOf
    [ nop_gen   f preV preR postV postR
    , dot_gen   f preV preR postV postR
    , v_ass_gen f preV preR postV postR
    , for_gen   f preV preR postV postR
    , if_gen    f preV preR postV postR
    , seq_gen   f preV preR postV postR
    , block_gen f preV preR postV postR
    , print_gen f preV preR postV postR
    ]

namespace Statements_given_preV_preR_postR

  public export
  0 Statement_postV_Gen : Type
  Statement_postV_Gen = SpecGen \rc => (preV : Variables) -> (preR : Registers rc) -> (postR : Registers rc) ->
                                       Gen (postV ** Statement preV preR postV postR)

  nop_gen   : Statement_postV_Gen
  dot_gen   : Statement_postV_Gen
  v_ass_gen : Statement_postV_Gen
  for_gen   : Statement_postV_Gen
  if_gen    : Statement_postV_Gen
  seq_gen   : Statement_postV_Gen
  block_gen : Statement_postV_Gen
  print_gen : Statement_postV_Gen

  export
  statement_gen : Statement_postV_Gen
  statement_gen Dry preV preR postR = oneOf
    [ nop_gen   Dry preV preR postR
    , dot_gen   Dry preV preR postR
    , v_ass_gen Dry preV preR postR
    , print_gen Dry preV preR postR
    ]
  statement_gen (More f) preV preR postR = oneOf
    [ nop_gen   f preV preR postR
    , dot_gen   f preV preR postR
    , v_ass_gen f preV preR postR
    , for_gen   f preV preR postR
    , if_gen    f preV preR postR
    , seq_gen   f preV preR postR
    , block_gen f preV preR postR
    , print_gen f preV preR postR
    ]

namespace Statements_given_preV_preR

  public export
  0 Statement_postV_postR_Gen : Type
  Statement_postV_postR_Gen = SpecGen \rc => (preV : Variables) -> (preR : Registers rc) -> Gen (postV ** postR ** Statement preV preR postV postR)

  nop_gen   : Statement_postV_postR_Gen
  dot_gen   : Statement_postV_postR_Gen
  v_ass_gen : Statement_postV_postR_Gen
  for_gen   : Statement_postV_postR_Gen
  if_gen    : Statement_postV_postR_Gen
  seq_gen   : Statement_postV_postR_Gen
  block_gen : Statement_postV_postR_Gen
  print_gen : Statement_postV_postR_Gen

  export
  statement_gen : Statement_postV_postR_Gen
  statement_gen Dry preV preR = oneOf
    [ nop_gen   Dry preV preR
    , dot_gen   Dry preV preR
    , v_ass_gen Dry preV preR
    , print_gen Dry preV preR
    ]
  statement_gen (More f) preV preR = oneOf
    [ nop_gen   f preV preR
    , dot_gen   f preV preR
    , v_ass_gen f preV preR
    , for_gen   f preV preR
    , if_gen    f preV preR
    , seq_gen   f preV preR
    , block_gen f preV preR
    , print_gen f preV preR
    ]

namespace Statements_given_preV_preR -- implementations

  nop_gen _ preV preR = pure (_ ** _ ** nop)

  dot_gen @{type'} @{name} @{_} _ preV preR = pure (_ ** _ ** !type'. !name)

  v_ass_gen @{_} @{_} @{expr} _ preV preR = do
    (n ** lk) <- lookupGen preV
    pure (_ ** _ ** n #= !expr)

  for_gen @{_} @{_} @{expr} f preV preR = do
    (insideV ** insideR ** init) <- statement_gen f preV preR
    --
    (updR ** _) <- eq_registers_gen f insideR
    upd         <- statement_gen f insideV insideR insideV updR
    --
    (bodyR ** _) <- eq_registers_gen f insideR
    (_ ** body)  <- statement_gen f insideV insideR bodyR
    --
    pure (_ ** _ ** for init !expr upd body)

  if_gen @{_} @{_} @{expr} f preV preR = do
    (_ ** _ ** th) <- statement_gen f preV preR
    (_ ** _ ** el) <- statement_gen f preV preR
    pure (_ ** _ ** if__ !expr th el)

  seq_gen f preV preR = do
    (midV ** midR ** l) <- statement_gen f preV preR
    (_    ** _    ** r) <- statement_gen f midV midR
    pure (_ ** _ ** l *> r)

  block_gen f preV preR = do
    (_ ** _ ** s) <- statement_gen f preV preR
    pure (_ ** _ ** block s)

  print_gen @{_} @{_} @{expr} _ preV preR = pure (_ ** _ ** print !(expr {ty=String'}))

namespace Statements_given_preV_preR_postV_postR -- implementations

  nop_gen _ preV preR postV postR = case (decEq postV preV, decEq postR preR) of
    (No _, _) => empty
    (_, No _) => empty
    (Yes Refl, Yes Refl) => pure nop

  dot_gen _ preV preR postV postR = case postV of
    [] => empty
    ((n, ty)::postV') => case (decEq postV' preV, decEq postR preR) of
      (No _, _) => empty
      (_, No _) => empty
      (Yes Refl, Yes Refl) => pure $ ty. n

  v_ass_gen @{_} @{_} @{expr} _ preV preR postV postR = case (decEq postV preV, decEq postR preR) of
    (No _, _) => empty
    (_, No _) => empty
    (Yes Refl, Yes Refl) => do
      (n ** lk) <- lookupGen preV
      pure $ n #= !expr

  for_gen @{_} @{_} @{expr} f preV preR postV postR = case decEq postV preV of
    No _ => empty
    Yes Refl => do
      (insideV ** init) <- statement_gen f preV preR postR
      --
      (updR ** _) <- eq_registers_gen f postR
      upd         <- statement_gen f insideV postR insideV updR
      --
      (bodyR ** _) <- eq_registers_gen f postR
      (_ ** body)  <- statement_gen f insideV postR bodyR
      --
      pure $ for init !expr upd body

  if_gen @{_} @{_} @{expr} f preV preR postV postR = case (decEq postV preV, @@ postR) of
    (Yes p, (Merge thR elR ** q)) => rewrite p in rewrite q in do
      (_ ** th) <- statement_gen f preV preR thR
      (_ ** el) <- statement_gen f preV preR elR
      pure $ if__ !expr th el
    _ => empty

  seq_gen f preV preR postV postR = do
    (midV ** midR ** left) <- statement_gen f preV preR
    right                  <- statement_gen f midV midR postV postR
    pure $ left *> right

  block_gen f preV preR postV postR = case decEq postV preV of
    No _ => empty
    Yes Refl => do
      (_ ** stmt) <- statement_gen f preV preR postR
      pure $ block stmt

  print_gen @{_} @{_} @{expr} _ preV preR postV postR = case (decEq postV preV, decEq postR preR) of
    (No _, _) => empty
    (_, No _) => empty
    (Yes Refl, Yes Refl) => pure $ print !(expr {ty=String'})

namespace Statements_given_preV_preR_postR -- implementations

  nop_gen _ preV preR postR = case decEq postR preR of
    No _ => empty
    Yes Refl => pure (_ ** nop)

  dot_gen @{type'} @{name} @{_} _ preV preR postR = case decEq postR preR of
    No _ => empty
    Yes Refl => pure (_ ** !type'. !name)

  v_ass_gen @{_} @{_} @{expr} _ preV preR postR = case decEq postR preR of
    No _ => empty
    Yes Refl => do
      (n ** lk) <- lookupGen preV
      pure (_ ** n #= !expr)

  for_gen @{_} @{_} @{expr} f preV preR postR = do
    (insideV ** init) <- statement_gen f preV preR postR
    --
    (updR ** _) <- eq_registers_gen f postR
    upd         <- statement_gen f insideV postR insideV updR
    --
    (bodyR ** _) <- eq_registers_gen f postR
    (_ ** body)  <- statement_gen f insideV postR bodyR
    --
    pure (_ ** for init !expr upd body)

  if_gen @{_} @{_} @{expr} f preV preR postR = case postR of
    Merge thR elR => do
      (_ ** th) <- statement_gen f preV preR thR
      (_ ** el) <- statement_gen f preV preR elR
      pure (_ ** if__ !expr th el)
    _ => empty

  seq_gen f preV preR postR = do
    (midV ** midR ** left) <- statement_gen f preV preR
    (_           ** right) <- statement_gen f midV midR postR
    pure $ (_ ** left *> right)

  block_gen f preV preR postR = do
    (_ ** stmt) <- statement_gen f preV preR postR
    pure $ (_ ** block stmt)

  print_gen @{_} @{_} @{expr} _ preV preR postR = case decEq postR preR of
    No _ => empty
    Yes Refl => pure $ (_ ** print !(expr {ty=String'}))
