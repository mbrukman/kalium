{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
module Kalium.Nucleus.Vector.Purify where

import Kalium.Prelude
import Kalium.Util

import Control.Monad.Reader
import Control.Monad.Writer
import Control.Monad.Except

import qualified Data.Map as M
import qualified Data.Set as S
import qualified Control.Dependent as Dep

import Kalium.Nucleus.Vector.Program
import Kalium.Nucleus.Vector.Recmap
import Kalium.Nucleus.Vector.Name

purify :: (MonadNameGen m) => EndoKleisli' m Program
purify program = do
    p1s <- execWriterT $ itraverse funcPurify (program ^. programFuncs)
    return $ Dep.restructure substituteSCC (resolve p1s) program

substituteSCC :: [PurifyInfo] -> EndoKleisli' Maybe Program
substituteSCC infoGroup program =
    let impureNames = S.fromList [ name | PurifyInfo name _ _ _ _ <- infoGroup ]
        program' = withPure
        dangling = program' `mentions` impureNames
        withoutImpure = S.foldr
            (\name -> programFuncs %~ M.delete name) program impureNames
        replacedCalls = withoutImpure & over recmapped purifyExpression
        withPure = replacedCalls & programFuncs %~ M.union pureFuncs
        pureFuncs = M.fromList $ do
            PurifyInfo _ _ name' func _ <- infoGroup
            return (name', func)
    in guard (not dangling) >> return program'
  where
    purifyExpression :: Endo' Expression
    purifyExpression = sofar appPurify infoGroup

type Request = (Name, Int)
data P1 = P1 Name Int Name (Pairs Name Name -> Maybe (Func, Set Request))

data PurifyInfo = PurifyInfo Name Int Name Func (Set Request)

instance Dep.Dependent PurifyInfo where
    type Name PurifyInfo = Request
    provides (PurifyInfo _ arity name' _ _) = (name', arity)
    depends (PurifyInfo _ _ _ _ reqs) = reqs

resolve = inContext getGen
  where
    getGen ps (P1 name arity name' gen) = maybeToList $ do
        (func, reqs) <- gen (map getNames ps)
        return (PurifyInfo name arity name' func reqs)
    getNames = \(P1 name _ name' _) -> (name, name')

funcPurify
    :: ( MonadNameGen m
       , MonadWriter [P1] m )
    => Name -> Func -> m ()
funcPurify (NameSpecial _) _ = return ()
funcPurify name (Func ty a) = do
    ( (ps,tys) , (a',ty') ) <- typeDrivenUnlambda ty a
    case ty' of
        TypeApp1 TypeTaint ty'' -> do
            let ty1 = tyfun tys ty''
                arity = length tys
                gen = expForcePurify' a'
                    & mapped . mapped . _1 %~ (Func ty1 . lambda ps)
            name' <- alias name
            tell [P1 name arity name' gen]
        _ -> return ()

expForcePurify
    :: ( MonadReader (Pairs Name Name) m
       , MonadError () m
       , MonadWriter (Set Request) m)
    => EndoKleisli' m Expression
expForcePurify = \case
    Taint a -> return a
    Follow p x a -> Into p <$> expForcePurify x <*> expForcePurify a
    Into p x a -> Into p x <$> expForcePurify a
    AppOp3 OpIf xElse xThen cond
         -> AppOp3 OpIf
        <$> expForcePurify xElse
        <*> expForcePurify xThen
        <*> pure cond
    (unbeta -> (Access name : es)) -> do
        let arity = length es
        name' <- asks (lookup name) >>= throwMaybe ()
        tell (S.singleton (name', arity))
        return (beta (Access name' : es))
    _ -> throwError ()

expForcePurify'
    :: Expression -> Pairs Name Name -> Maybe (Expression, Set Request)
expForcePurify' = fmap runError . runReaderT . runWriterT . expForcePurify
    where runError = either (const Nothing) Just . runExcept

appPurify :: PurifyInfo -> Expression -> Maybe Expression
appPurify (PurifyInfo name arity name' _ _) e
    | (Access op:es) <- unbeta e, op == name
    , arity == length es
    = Just $ Taint . beta $ (Access name' : es)
appPurify _ _ = Nothing
