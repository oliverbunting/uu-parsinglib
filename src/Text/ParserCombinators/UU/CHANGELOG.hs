-- | This module just contains the CHANGELOG
-- Version 2.5.6
--
--      *  added a special version of \<|\> (called '<-|->') in @ExtAlternative@ which does not compare the length of the parsers; to be used in permutations
--
-- Version 2.5.5.2
--
--      *  type signatures were added to make Haddock happy
--
-- Version 2.5.5.1
--
--      *  type signatures were added to make the library GHC 7 ready.
--
-- Version 2.5.5
--
--      *  preference is given to earlier accept steps in order to avoid infinite insertions in case of otherwise equivalent repair strategies
--
-- Version 2.5.4.2
--
--      * fixed small problem in <?> so it gets its chance to do its work
--
-- Version 2.5.4.1
--
--      * added a @pSem@ which makes it possible to tell how certain components of merged structures are to be combined before exposing all elements to the outer sem: 
--
-- >  run ( (,)  `pMerge` ( ((++) `pSem` (pMany pa <||> pMany pb)) <||> pOne pc))  "abcaaab"
-- >
-- >  Result: (["a","a","a","a","b","b"],"c")
--
--      * added a @pMergedSep@, which allows you to specify a separator between two merged elements
--
-- >  run ((((,), pc) `pMergeSep` (pMany pa <||> pMany pb))) "acbcacbc"
-- >
-- > Result: (["a","a","a"],["b","b"])
-- > Correcting steps: 
-- >    Inserted 'a' at position (0,8) expecting one of ['b', 'a']
--
-- Version 2.5.4
--
--      * made the merging combinators more general introducing  @pAtMost@, @pBetween@ and  @pAtLeast@; examples are extended; see @`demo_merge`@
--
--      * used CPP in order to generate demo's easily
--
--      * fixed a bug which made @pPos@ ambiguous
--
--      * modified haddock stuff
--
-- Version 2.5.3
--
--      * fixed a bug in the implementation; some functions were too strict, due to introduction of nice abstractions!!
--
--      * added a generalisation of @`pMerged`@ and @`pPerms`@ to the module "Text.ParserCombinators.UU.Derived";  the old modules have been marked as deprecated
--
--      * removed the old module Text.ParserCombinators.UU.Parsing, which was already marged as deprecated
--
-- Version 2.5.2
-- 
--      * fixed a bug in sequential composition with a pure as left hand side
--
--      * added an experimental @pMerge@, which combines the featurs of @pPerms@ and @pMerged@
--
--   Version 2.5.1.1
-- 
--       * Now with the correct Changelog
--
--  Version 2.5.1 
--
--       * added the permutation parsers from the old uulib
--
--       * extended the abstract interpretation so more soundness checks can be done statically
--
--       * everything seems to work; in case of problems please report and go back to 2.5.0
--
--   Version 2.5.0
--   
--       * generalised over the position in the input; now it is easy to maintain e.g. (line,column) info as shown in the "Examples.hs" file
--
--       * added needed instances for @String@ s as input in "BasicInstances.hs"
--     
--       * fixed a bug in pMunch where a Step was inserted with 0 progress, leading to infinite insertions 
--
--       * added Haddock beautifications
--
--  Version 2.4.5
--       
--       * added the function @`pPos`@ for retreiving the current input position
--       
--  Version 2.4.4
--       
--       * solved a mistake which had crept in in the greedy choice
--       
--       * added priority for @`<<|>`@ which had disappeared
--       
--       * added an example how to achieve the effect of manytill from parsec
-- 
--  Version 2.4.3
--
--       * removed the classes IsParser and Symbol, which made the code shorter and more H98-alike
--         last version with dynamic error message computation
--
--  Version 2.4.2
--
--       * fixed dependency in cabal file to base >=4.2
--
--       * moved definition of <$ to the class Functor and removed the class ExtApplicative 
--
--  Version 2.4.1
--
--       * added the module Text.ParserCombinators.Merge for recognizing alternating sequences
--
--       * made @P st@ an instance of @`MonadPlus`@
--
--       * beautified Haddock documentation
--
--  Version 2.4.0
--
--       * contains abstract interpretation for minimal lenth, in order to avoid recursive correction process
--
--       * idem for checking that no repeating combinators like pList are parameterised with possibly empty parsers
--
--       * lots of Haddcock doumentation in "Text.ParserCombinators.UU.Examples"
--
--  Version 2.3.4
--
--       * removed dependecies on impredictaive types, preparing for next GHC version
--
--  Version 2.3.3
--
--       * added `pMunch` which takes a Boolean function, and recognises the longest prefix for which the symbols match the predicate
-- 
--       * added the infix operator with piority 2 @\<?> :: P state a -> String -> P state a@ which replaces the list of expected symbols
--         in error message by its right argument String
--
--  Version 2.3.2
--
--       * added microsteps, which can be used to disambiguate
--
-- Version 2.3.1
--
--       * fix for GHC 6.12, because of change in GADT definition handling
--
-- Versions above 2.2:
--
--       *  make use of type families
--   
--       *  contain a module with many list-based derived combinators
--
-- Versions above 2.1: 
--       * based on Control.Applicative
--
--    Note that the basic parser interface will probably not change much when we add more features, but the calling conventions
--    of the outer parser and the class structure upon which the parametrisation is based may change slightly

module Text.ParserCombinators.UU.CHANGELOG () where


dummy = undefined
