module UseGen

import Data.List.Lazy

import Test.DepTyCheck.Gen

import System.Random.Pure.StdGen

%default total

%cg chez lazy=weakMemo

fun : Gen0 $ List Int
fun = do
  let nums = elements [1 .. 100]
  a <- nums
  b <- nums
  c <- nums
  d <- nums
  e <- nums
  f <- nums
  pure [a, b, c, d, e, f]

main : IO Unit
main = Lazy.traverse_ printLn $ unGenTryN 10 someStdGen fun
