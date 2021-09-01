module Test.DepTyCheck.Gen.Auto.Checked

import public Control.Monad.Reader
import public Control.Monad.Trans
import public Control.Monad.Writer

import public Data.Vect.Extra
import public Data.SortedMap
import public Data.SortedSet

import public Language.Reflection.Types

import public Syntax.WithProof

import public Test.DepTyCheck.Gen.Auto.Util

%default total

-----------------------------------------------------
--- Data types for the safe signature formulation ---
-----------------------------------------------------

public export
data ArgExplicitness = ExplicitArg | ImplicitArg

public export
Eq ArgExplicitness where
  ExplicitArg == ExplicitArg = True
  ImplicitArg == ImplicitArg = True
  _ == _ = False

namespace ArgExplicitness

  public export
  (.toTT) : ArgExplicitness -> PiInfo a
  (.toTT) ExplicitArg = ExplicitArg
  (.toTT) ImplicitArg = ImplicitArg

------------------------------------------------------------------
--- Datatypes to describe signatures after checking user input ---
------------------------------------------------------------------

public export
data NamesOrigin = CustomNames | FromDataDef

public export
record GenSignature (nso : NamesOrigin) where
  constructor MkGenSignature
  targetType : TypeInfo
  givenParams : SortedMap (Fin targetType.args.length) $ case nso of
                                                           CustomNames => (ArgExplicitness, Name)
                                                           FromDataDef => ArgExplicitness

namespace GenSignature

  characteristics : GenSignature cn -> (String, List Nat)
  characteristics (MkGenSignature ty giv) = (show ty.name, toNatList $ keys giv)

public export
Eq (GenSignature cn) where
  (==) = (==) `on` characteristics

public export
Ord (GenSignature cn) where
  compare = comparing characteristics

public export
record GenExternals where
  constructor MkGenExternals
  externals : SortedSet $ GenSignature CustomNames

-----------------------------------
--- "Canonical" functions stuff ---
-----------------------------------

--- Main interfaces ---

public export
interface Monad m => CanonicName m where
  canonicName : {nso : _} -> GenSignature nso -> m Name

--- Canonic signature functions --

-- Must respect names from the `givenParams` field, at least for implicit parameters
-- The current implementation expects that names in the given signature
--   - do not repeat and
--   - are not equal to names of generated parameters as declared in the target type's definition.
export
canonicSig : GenSignature CustomNames -> TTImp
canonicSig sig = piAll returnTy $ arg <$> toList sig.givenParams where
  -- TODO Check that the resulting `TTImp` reifies to a `Type`? During this check, however, all types must be present in the caller's context.

  -- should be a memoized constant
  givensRenamingRules : SortedMap Name Name
  givensRenamingRules = fromList $ mapMaybeI' sig.targetType.args $ \idx, (MkArg {name, _}) => (name,) . snd <$> lookup idx sig.givenParams

  -- Renames all names that are present in the target type declaration to their according names in the gen signature
  renameGivens : TTImp -> TTImp
  renameGivens = substNameBy givensRenamingRules

  arg : (Fin sig.targetType.args.length, ArgExplicitness, Name) -> Arg False
  arg (idx, expl, name) = MkArg MW .| expl.toTT .| Just name .| renameGivens (index' sig.targetType.args idx).type

  returnTy : TTImp
  returnTy = var `{Test.DepTyCheck.Gen.Gen} .$ buildDPair targetTypeApplied generatedArgs where

    targetTypeApplied : TTImp
    targetTypeApplied = foldr apply (var sig.targetType.name) $ reverse $ mapI' sig.targetType.args $ \idx, (MkArg {name, piInfo, _}) =>
                          let name = maybe name snd $ lookup idx sig.givenParams in
                          case piInfo of
                            ExplicitArg   => (.$ var name)
                            ImplicitArg   => \f => namedApp f name $ var name
                            DefImplicit _ => \f => namedApp f name $ var name
                            AutoImplicit  => (`autoApp` var name)

    generatedArgs : List (Name, TTImp)
    generatedArgs = mapMaybeI' sig.targetType.args $ \idx, (MkArg _ _ name type) =>
                      case lookup idx sig.givenParams of
                        Nothing => Just (name, renameGivens type)
                        Just _  => Nothing

export
callCanonicGen : CanonicName m => {nso : _} -> (sig : GenSignature nso) -> Vect sig.givenParams.asList.length TTImp -> m TTImp
callCanonicGen sig values = do
  topmostName <- canonicName sig
  let (givenParams ** prfAsSig) = @@ sig.givenParams.asList
  pure $ foldl (flip apply) (var topmostName) $ flip mapWithPos values $ \valueIdx, value =>
    let (paramIdx, info) = index' givenParams $ rewrite sym prfAsSig in valueIdx in
    let (expl, name) : (ArgExplicitness, Name) = case nso of
                                                   CustomNames => info
                                                   FromDataDef => (info, nm $ index' sig.targetType.args paramIdx)
    in case expl of
      ExplicitArg => (.$ value)
      ImplicitArg => \f => namedApp f name value

  where
    nm : Arg True -> Name -- workaround of some type inference bug
    nm = name

export
deriveCanonical : CanonicName m => GenSignature nso -> m Decl
deriveCanonical sig = do
  ?deriveCanonical_rhs

--- Implementations for the canonic interfaces ---

MonadReader (SortedMap (GenSignature nso) Name) m =>
MonadWriter (SortedMap (GenSignature nso) $ Lazy Decl) m =>
CanonicName m where
  canonicName sig = do
    ?canonocName_impl

--- Canonic-dischagring function ---

export
runCanonic : GenExternals -> (forall m. CanonicName m => m a) -> Elab (a, List Decl)
runCanonic exts calc = ?runCanonic_rhs
