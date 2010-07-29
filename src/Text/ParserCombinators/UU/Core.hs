 
{-# LANGUAGE  RankNTypes, 
              GADTs,
              MultiParamTypeClasses,
              FunctionalDependencies #-}

-- | The module `Core` contains the basic functionality of the parser library. 
--   It  uses the  breadth-first module  to realise online generation of results, the error
--   correction administration, dealing with ambigous grammars; it defines the types  of the elementary  parsers
--   and  recognisers involved.For typical use cases of the libray see the module @"Text.ParserCombinators.UU.Examples"@

module Text.ParserCombinators.UU.Core ( module Text.ParserCombinators.UU.Core
                                      , module Control.Applicative) where
import Control.Applicative  hiding  (many, some, optional)
import Char
import Debug.Trace
import Maybe


infix   2  <?>    -- should be the last element in a sequence of alternatives
infixl  3  <<|>   -- intended use p <<|> q <<|> r <|> x <|> y <?> z


-- ** `Provides'

-- | The function `splitState` playes a crucial role in splitting up the state. The `symbol` parameter tells us what kind of thing, and even which value of that kind, is expected from the input.
--   The state  and  and the symbol type together determine what kind of token has to be returned. Since the function is overloaded we do not have to invent 
--   all kind of different names for our elementary parsers.
class  Provides state symbol token | state symbol -> token  where
       splitState   ::  symbol -> (token -> state  -> Steps a) -> state -> Steps a

-- ** `Eof'

class Eof state where
       eof          ::  state   -> Bool
       deleteAtEnd  ::  state   -> Maybe (Cost, state)



-- * The type  describing parsers: @`P`@
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%% Parsers     %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

data  P   st  a =  P  (forall r . (a  -> st -> Steps r)  -> st -> Steps       r  ) --  history parser
                      (forall r . (      st -> Steps r)  -> st -> Steps   (a, r) ) --  future parser
                      (forall r . (      st -> Steps r)  -> st -> Steps       r  ) --  recogniser
                      Nat                                                          --  minimal length
                      (Maybe a)                                                    --  possibly empty with value     

-- ** Parsers are functors:  @`fmap`@
instance   Functor (P  state) where 
  fmap f   (P   ph pf pr l me)   =  P  ( \  k -> ph ( k .f ))
                                       ( \  k ->  pushapply f . pf k) -- pure f <*> pf
                                       (pr) 
                                       l
                                       (fmap f me)
  f <$   (P _  _  qr ql qe)   
    = P ( qr . ($f)) (\ k st -> push f (qr k st)) qr  ql  (case qe of Nothing -> Nothing; _ -> Just f)


-- ** Parsers are Applicative:  @`<*>`@,  @`<*`@,  @`*>`@ and  @`pure`@
instance   Applicative (P  state) where
  P ph pf pr pl pe <*> ~(P qh qf qr ql qe)  =  P  ( \  k -> ph (\ pr -> qh (\ qr -> k (pr qr))))
                                                  ((apply .) . (pf .qf))
                                                  ( pr . qr)
                                                  (nat_add pl ql)
                                                  (pe <*> qe)
  P ph pf pr pl pe <*  ~(P _  _  qr ql qe)   = P  ( ph. (qr.))  (pf. qr)   (pr . qr)
                                                  (nat_add pl ql) 
                                                  (case qe of Nothing -> Nothing ; _ -> pe)
  P _  _  pr pl pe *>  ~(P qh qf qr ql qe)   = P ( pr . qh  )  (pr. qf)    (pr . qr)           
                                                 (nat_add pl ql) (case pe of Nothing -> Nothing ; _ -> qe) 
  pure a                                     =  P  ($a) ((push a).) id Zero (Just a)


-- ** Parsers are Alternative:  @`<|>`@ and  @`empty`@ 
instance   Alternative (P   state) where 
  P ph pf pr pl pe <|> P qh qf qr ql qe 
    =  let (rl, b) = nat_min pl ql
           bestx :: Steps a -> Steps a -> Steps a
           bestx = if b then flip best else best 
       in    P (\  k inp  -> ph k inp `bestx` qh k inp)
               (\  k inp  -> pf k inp `bestx` qf k inp)
               (\  k inp  -> pr k inp `bestx` qr k inp)
               rl
               (case (pe, qe)  of
                 (Nothing, _      ) -> qe
                 (_      , Nothing) -> pe
                 (_      , _      ) -> error "ambiguous parser because two sides of choice can be empty")
  empty                =  P  ( \  k inp  ->  noAlts)
                             ( \  k inp  ->  noAlts)
                             ( \  k inp  ->  noAlts)
                             Infinite
                             Nothing

-- ** Parsers can recognise single tokens:  @`pSym`@ and  @`pSymExt`@
-- | Many parsing libraries do not make a distinction between the terminal symbols of the language recognised 
--   and the tokens actually constructed from the  input. 
--   This happens e.g. if we want to recognise an integer or an identifier: 
--   we are also interested in which integer occurred in the input, or which identifier. 
--   The function `pSymExt` takes as argument a value of some type `symbol', and returns a value of type `token'. The parser will in general depend on some 
--   state which is maintained holding the input. The functional dependency fixes the `token` type, based on the `symbol` type and the type of the parser `p`.
--   Since `pSymExt' is overloaded both the type and the value of symbol determine how to decompose the input in a `token` and the remaining input.
--   `pSymExt`  takes two extra parameters: one describing the minimal numer of tokens recognised, 
--   and the second whether the symbol can recognise the empty string and the value which is to be returned in that case
  
pSymExt ::   (Provides state symbol token) => Nat -> Maybe token -> symbol -> P state token

  
pSymExt l e a  = P ( \ k inp -> splitState a k inp)
                   ( \ k inp -> splitState a (\ t inp' -> push t (k inp')) inp)
                   ( \ k inp -> splitState a (\ _ inp' -> k inp') inp)
                   l
                   e
-- | @`pSym`@ covers the most common case of recognsiing a symbol: a single token is removed form the input, and it cannot recognise the empty string
pSym    ::   (Provides state symbol token) =>                       symbol -> P state token
pSym  s   = pSymExt (Succ Zero) Nothing s 

-- ** Parsers are Monads:  @`>>=`@ and  @`return`@

unParser_h (P  h   _  _  _ _)  =  h
unParser_f (P  _   f  _  _ _)  =  f
unParser_r (P  _   _  r  _ _)  =  r
          

instance  Monad (P st) where
       P  ph pf pr pl pe >>=  a2q = 
                P  (  \k -> ph (\ a -> unParser_h (a2q a) k))
                   (  \k -> ph (\ a -> unParser_f (a2q a) k))
                   (  \k -> ph (\ a -> unParser_r (a2q a) k))
                   (nat_add pl (error "cannot compute minimal length of right hand side of monadic parser"))
                   (case pe of
                    Nothing -> Nothing
                    Just a -> let (P _ _ _ _ a2qv) = a2q a in a2qv)
       return  = pure 

-- * Additional useful combinators
-- ** Controlling the text of error reporting:  @`<?>`@
-- | The parsers build a list of symbols which are expected at a specific point. 
--   This list is used to report errors.
--   Quite often it is more informative to get e.g. the name of the non-terminal. 
--   The @`<?>`@ combinator replaces this list of symbols by it's righ-hand side argument.

(<?>) :: P state a -> String -> P state a
P  ph  pf  pr  pl pe <?> label = P ( \ k inp -> replaceExpected  ( ph k inp))
                                   ( \ k inp -> replaceExpected  ( pf k inp))
                                   ( \ k inp -> replaceExpected  ( pr k inp))
                                   pl
                                   pe
                           where replaceExpected (Fail _ c) = (Fail [label] c)
                                 replaceExpected others     = others


-- ** An alternative for the Alternative, which is greedy:  @`<<|>`@
-- | `<<|>` is the greedy version of `<|>`. If its left hand side parser can make some progress that alternative is comitted. Can be used to make parsers faster, and even
--   get a complete Parsec equivalent behaviour, with all its (dis)advantages. use with are!

P ph pf pr pl pe <<|> P qh qf qr ql qe 
    = let (rl, b) = nat_min pl ql
          bestx = if b then flip best else best
      in   P ( \ k st  -> let left = norm (ph k st) 
                          in if has_success left then left
                             else left `bestx` norm (qh k st))
             ( \ k st  ->  let left = norm (pf k st) 
                           in if has_success left then left
                              else left `bestx` norm (qf k st))
             ( \ k st  ->  let left = norm (pr k st) 
                           in if has_success left then left
                              else left `bestx` norm (qr k st))
             rl
             (case (pe, qe)  of
                 (Nothing, _      ) -> qe
                 (_      , Nothing) -> pe
                 (_      , _      ) -> error "ambiguous parser because two sides of choice can be empty")

-- ** Parsers can be disambiguated using micro-steps:  @`micro`@
-- | `micro` inserts a `Cost` step into the sequence representing the progress the parser is making; for its use see `Text.ParserCombinators.UU.Examples` 
P ph pf pr pl pe `micro` i = P ( \ k st -> ph (\ a st -> Micro i (k a st)) st)
                               ( \ k st -> pf (Micro i .k) st)
                               ( \ k st -> pr (Micro i .k) st)
                               pl
                               pe 

-- ** Dealing with (non-empty) Ambigous parsers: @`amb`@ 
--   For the precise functionng of the combinators we refer to the technical report mentioned in the README file
--   @`amb`@ converts an ambiguous parser into a parser which returns a list of possible recognitions.
amb :: P st a -> P st [a]

amb (P ph pf pr pl pe) = P ( \k     ->  removeEnd_h . ph (\ a st' -> End_h ([a], \ as -> k as st') noAlts))
                           ( \k inp ->  combinevalues . removeEnd_f $ pf (\st -> End_f [k st] noAlts) inp)
                           ( \k     ->  removeEnd_h . pr (\ st' -> End_h ([undefined], \ _ -> k  st') noAlts))
                           pl
                           (fmap pure pe)
                         where  combinevalues  :: Steps [(a,r)] -> Steps ([a],r)
                                combinevalues lar           =   Apply (\ lar -> (map fst lar, snd (head lar))) lar

       
-- ** Parse errors can be retreived from the state: @`pErrors`@
-- | `getErrors` retreives the correcting steps made since the last time the function was called. The result can, 
--   using a monad, be used to control how to--    proceed with the parsing process.

class state `Stores`  error | state -> error where
  getErrors    ::  state   -> ([error], state)

pErrors :: Stores st error => P st [error]
pErrors = P ( \ k inp -> let (errs, inp') = getErrors inp in k    errs    inp' )
            ( \ k inp -> let (errs, inp') = getErrors inp in push errs (k inp'))
            ( \ k inp -> let (errs, inp') = getErrors inp in            k inp' )
            Zero       -- this parser does not consume input
            (Just [])  -- the errors consumed cannot be determined statically! Hence we assume none.

-- ** Starting and finalising the parsing process: @`pEnd`@ and @`parse`@
-- | The function `pEnd` should be called at the end of the parsing process. It deletes any unsonsumed input, and reports its preence as an eror.

pEnd    :: (Stores st error, Eof st) => P st [error]
pEnd    = P ( \ k inp ->   let deleterest inp =  case deleteAtEnd inp of
                                                    Nothing -> let (finalerrors, finalstate) = getErrors inp
                                                               in k  finalerrors finalstate
                                                    Just (i, inp') -> Fail []  [const (i,  deleterest inp')]
                           in deleterest inp)
            ( \ k   inp -> let deleterest inp =  case deleteAtEnd inp of
                                                    Nothing -> let (finalerrors, finalstate) = getErrors inp
                                                               in push finalerrors (k finalstate)
                                                    Just (i, inp') -> Fail [] [const ((i, deleterest inp'))]
                           in deleterest inp)
            ( \ k   inp -> let deleterest inp =  case deleteAtEnd inp of
                                                    Nothing -> let (finalerrors, finalstate) = getErrors inp
                                                               in  (k finalstate)
                                                    Just (i, inp') -> Fail [] [const (i, deleterest inp')]
                           in deleterest inp)
            Zero
            (error "Unforeseen use of pEnd function; pEnd should only be used in function running the actual parser")


-- The function @`parse`@ shows the prototypical way of running a parser on a some specific input
-- By default we use the future parser, since this gives us access to partal result; future parsers are expected to run in less space
parse :: (Eof t) => P t a -> t -> a
parse   (P _  pf _ _ _)  = fst . eval . pf  (\ rest   -> if eof rest then succeedAlways        else error "pEnd missing?")
parse_h (P ph _  _ _ _)  = fst . eval . ph  (\ a rest -> if eof rest then push a failAlways else error "pEnd missing?") 

-- ** The state may be temporarily change type: @`pSwitch`@
-- | `pSwitch` takes the current state and modifies it to a different type of state to which its argument parser is applied. 
--   The second component of the result is a function which  converts the remaining state of this parser back into a valuee of the original type.

pSwitch :: (st1 -> (st2, st2 -> st1)) -> P st2 a -> P st1 a
pSwitch split (P ph pf pr pl pe)    = P (\ k st1 ->  let (st2, back) = split st1
                                                     in ph (\ a st2' -> k a (back st2')) st2)
                                        (\ k st1 ->  let (st2, back) = split st1
                                                     in pf (\st2' -> k (back st2')) st2)
                                        (\ k st1 ->  let (st2, back) = split st1
                                                     in pr (\st2' -> k (back st2')) st2)
                                        pl
                                        pe 

-- * Maintaining Progress Information
-- | The data type @`Steps`@ is the core data type around which the parsers are constructed.
--   It is a describes a tree structure of streams containing (in an interleaved way) both the online result of the parsing process,
--   and progress information. Recognising an input token should correspond to a certain amount of @`Progress`@, 
--   which tells how much of the input state was consumed. 
--   The @`Progress`@ is used to implement the breadth-first search process, in which alternatives are
--   examined in a more-or-less synchonised way. The meaning of the various @`Step`@ constructors is as follows:
--
--   [@`Step`@] A token was succesfully recognised, and as a result the input was 'advanced' by the distance  @`Progress`@
--
--   [@`Apply`@] The type of value represented by the `Steps` changes by applying the function parameter.
--
--   [@`Fail`@] A correcting step has to made to the input; the first parameter contains information about what was expected in the input, 
--   and the second parameter describes the various corrected alternatives, each with an associated `Cost`
--
--   [@`Micro`@] A small cost is inserted in the sequence, which is used to disambiguate. Use with care!
--
--   The last two alternatives play a role in recognising ambigous non-terminals. For a full description see the technical report referred to from the README file..

type Cost = Int
type Progress = Int
type Strings = [String]

data  Steps   a  where
      Step   ::                 Progress       ->  Steps a                             -> Steps   a
      Apply  ::  forall a b.    (b -> a)       ->  Steps   b                           -> Steps   a
      Fail   ::                 Strings        ->  [Strings   ->  (Cost , Steps   a)]  -> Steps   a
      Micro   ::                 Cost           ->  Steps a                             -> Steps   a
      End_h  ::                 ([a] , [a]     ->  Steps r)    ->  Steps   (a,r)       -> Steps   (a, r)
      End_f  ::                 [Steps   a]    ->  Steps   a                           -> Steps   a

succeedAlways = let steps = Step 0 steps in steps
failAlways  =  Fail [] [const (0, failAlways)]
noAlts      =  Fail [] []

has_success (Step _ _) = True
has_success _        = False

-- ! @`eval`@ removes the progress information from a sequence of steps, and constructs the value contained in it. 
eval :: Steps   a      ->  a
eval (Step  _    l)     =   eval l
eval (Micro  _    l)     =   eval l
eval (Fail   ss  ls  )  =   trace' ("expecting: " ++ show ss) (eval (getCheapest 3 (map ($ss) ls))) 
eval (Apply  f   l   )  =   f (eval l)
eval (End_f   _  _   )  =   error "dangling End_f constructor"
eval (End_h   _  _   )  =   error "dangling End_h constructor"

push        :: v -> Steps   r -> Steps   (v, r)
push v      =  Apply (\ r -> (v, r))
apply       :: Steps (b -> a, (b, r)) -> Steps (a, r)
apply       =  Apply (\(b2a, ~(b, r)) -> (b2a b, r)) 
pushapply   :: (b -> a) -> Steps (b, r) -> Steps (a, r)
pushapply f = Apply (\ (b, r) -> (f b, r)) 

norm ::  Steps a ->  Steps   a
norm     (Apply f (Step   p    l  ))   =   Step  p (Apply f l)
norm     (Apply f (Micro  c    l  ))   =   Micro c (Apply f l)
norm     (Apply f (Fail   ss   ls ))   =   Fail ss (applyFail (Apply f) ls)
norm     (Apply f (Apply  g    l  ))   =   norm (Apply (f.g) l)
norm     (Apply f (End_f  ss   l  ))   =   End_f (map (Apply f) ss) (Apply f l)
norm     (Apply f (End_h  _    _  ))   =   error "Apply before End_h"
norm     steps                         =   steps

applyFail f  = map (\ g -> \ ex -> let (c, l) =  g ex in  (c, f l))

best :: Steps   a -> Steps   a -> Steps   a
x `best` y =   norm x `best'` norm y

best' :: Steps   b -> Steps   b -> Steps   b
Fail  sl  ll     `best'`  Fail  sr rr     =   Fail (sl ++ sr) (ll++rr)
Fail  _   _      `best'`  r               =   r
l                `best'`  Fail  _  _      =   l
Step  n   l      `best'`  Step  m  r
    | n == m                              =   Step n (l `best'` r)     
    | n < m                               =   Step n (l  `best'`  Step (m - n)  r)
    | n > m                               =   Step m (Step (n - m)  l  `best'` r)
ls@(Step _  _)    `best'`  Micro _ _        =  ls
Micro _    _      `best'`  rs@(Step  _ _)   =  rs
ls@(Micro i l)    `best'`  rs@(Micro j r)  
    | i == j                               =   Micro i (l `best'` r)
    | i < j                                =   ls
    | i > j                                =   rs
End_f  as  l            `best'`  End_f  bs r          =   End_f (as++bs)  (l `best` r)
End_f  as  l            `best'`  r                    =   End_f as        (l `best` r)
l                       `best'`  End_f  bs r          =   End_f bs        (l `best` r)
End_h  (as, k_h_st)  l  `best'`  End_h  (bs, _) r     =   End_h (as++bs, k_h_st)  (l `best` r)
End_h  as  l            `best'`  r                    =   End_h as (l `best` r)
l                       `best'`  End_h  bs r          =   End_h bs (l `best` r)
l                       `best'`  r                    =   l `best` r 

-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%% getCheapest  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

getCheapest :: Int -> [(Int, Steps a)] -> Steps a 
getCheapest _ [] = error "no correcting alternative found"
getCheapest n l  =  snd $  foldr (\(w,ll) btf@(c, l)
                               ->    if w < c   -- c is the best cost estimate thus far, and w total costs on this path
                                     then let new = (traverse n ll w c) 
                                          in if new < c then (new, ll) else btf
                                     else btf 
                               )   (maxBound, error "getCheapest") l


traverse :: Int -> Steps a -> Int -> Int  -> Int 
traverse 0  _                =  trace' ("traverse " ++ show 0 ++ "\n") (\ v c ->  v)
traverse n (Step _   l)      =  trace' ("traverse Step   " ++ show n ++ "\n") (traverse (n -  1 ) l)
traverse n (Micro _  l)      =  trace' ("traverse Micro  " ++ show n ++ "\n") (traverse n         l)
traverse n (Apply _  l)      =  trace' ("traverse Apply  " ++ show n ++ "\n") (traverse n         l)
traverse n (Fail m m2ls)     =  trace' ("traverse Fail   " ++ show n ++ "\n") (\ v c ->  foldr (\ (w,l) c' -> if v + w < c' then traverse (n -  1 ) l (v+w) c'
                                                                                                           else c'
                                                                                            ) c (map ($m) m2ls)
                                                                    )
traverse n (End_h ((a, lf))    r)  =  traverse n (lf a `best` removeEnd_h r)
traverse n (End_f (l      :_)  r)  =  traverse n (l `best` r) 

-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%% Handling ambiguous paths             %%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

removeEnd_h     :: Steps (a, r) -> Steps r
removeEnd_h (Fail  m ls             )  =   Fail m (applyFail removeEnd_h ls)
removeEnd_h (Step  ps l             )  =   Step  ps (removeEnd_h l)
removeEnd_h (Apply f l              )  =   error "not in history parsers"
removeEnd_h (Micro c l              )  =   Micro c (removeEnd_h l)
removeEnd_h (End_h  (as, k_st  ) r  )  =   k_st as `best` removeEnd_h r 

removeEnd_f      :: Steps r -> Steps [r]
removeEnd_f (Fail m ls)        =   Fail m (applyFail removeEnd_f ls)
removeEnd_f (Step ps l)        =   Step ps (removeEnd_f l)
removeEnd_f (Apply f l)        =   Apply (map' f) (removeEnd_f l) 
                                   where map' f ~(x:xs)  =  f x : map f xs
removeEnd_f (Micro c l      )  =   Micro c (removeEnd_f l)
removeEnd_f (End_f(s:ss) r)    =   Apply  (:(map  eval ss)) s 
                                                 `best`
                                          removeEnd_f r
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%% Auxiliary Functions and Types        %%%%%%%%%%%%%%%%%%%
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

trace' v m = m 

-- * Auxiliary functions and types
-- ** Checking for non-sensical combinations: @`must_be_non_empty`@ and @`must_be_non_empties`@
-- | The function checks wehther its second argument is a parser which can recognise the mety sequence. If so an error message is given
--   using the name of the context. If not then the third argument is returned. This is useful in testing for loogical combinations. For its use see
--   the module Text>parserCombinators.UU.Derived

must_be_non_empty :: [Char] -> P t t1 -> t2 -> t2
must_be_non_empty msg p@(P _ _ _ _ (Just _ )) _ 
            = error ("The combinator " ++ msg ++ "\n" ++
                     "    requires that it's argument cannot recognise the empty string\n")
must_be_non_empty _ _  q  = q

-- | This function is similar to the above, but can be used in situations where we recognise a sequence of elements separated by other elements. This does not 
--   make sense if both parsers can recognise the empty string. Your grammar is then highly ambiguous.

must_be_non_empties :: [Char] -> P t1 t -> P t3 t2 -> t4 -> t4
must_be_non_empties  msg (P _ _ _ _ (Just _ )) (P _ _ _ _ (Just _ )) _ 
            = error ("The combinator " ++ msg ++ "\n" ++
                     "    requires that not both arguments can recognise the empty string\n")
must_be_non_empties  msg _  _ q = q

-- ** The type @`Nat`@ for describing the minimal number of tokens consumed
-- | The data type @`Nat`@ is used to represent the minimal length of a parser.
--   Care should be taken in order to not evaluate the right hand side of the binary functions @`nat_min`@ and @`nat-add`@ more than necesssary.

data Nat = Zero
         | Succ Nat
         | Infinite
         deriving  Show

nat_min Zero       _          = trace' "Left Zero in nat_min\n"     (Zero, True)
nat_min Infinite   r          = trace' "Left Infinite in nat_min\n" (r,    False) 
nat_min l          Infinite   = trace' "Right Zero in nat_min\n"    (l,    True)
nat_min _          Zero       = trace' "Right Zero in nat_min\n"    (Zero, False) 
nat_min (Succ ll)  (Succ rr)  = trace' "Succs in nat_min\n"         (let (v, b) = ll `nat_min` rr in (Succ v, b))

nat_add Infinite  _ = trace' "Infinite in add\n" Infinite
nat_add Zero      r = trace' "Zero in add\n"     r
nat_add (Succ l)  r = trace' "Succ in add\n"     (Succ (nat_add l r))

get_length (P _ _ _ l _) = l



