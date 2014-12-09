{-# LANGUAGE FlexibleInstances #-}
module Sodium.Haskell.Sugar where

import Control.Applicative
import Control.Lens

import Language.Haskell.Exts
import Sodium.Util (closureM)

sugarcoat :: (Applicative m, Monad m) => Module -> m Module
sugarcoat = closureM sugar

class Sugar a where
    sugar :: (Applicative m, Monad m) => a -> m a

instance (Sugar a, Traversable f) => Sugar (f a) where
    sugar = traverse sugar

instance Sugar Module where
    sugar (Module srcLoc name pragmas wtext exportSpec importDecls           decls)
        =  Module srcLoc name pragmas wtext exportSpec importDecls <$> sugar decls

instance Sugar Decl where
    sugar = \case
        FunBind matches -> FunBind <$> sugar matches
        decl -> pure decl

instance Sugar Match where
    sugar (Match srcLoc name pats ty rhs binds) = do
        (pats', rhs') <- sugar rhs <&> \case
            UnGuardedRhs (Lambda _ pats' exp)
                 -> (pats ++ pats', UnGuardedRhs exp)
            rhs' -> (pats, rhs')
        Match srcLoc name pats' ty rhs' <$> sugar binds

instance Sugar Binds where
    sugar = \case
        IPBinds {} -> error "not supported: IPBinds"
        BDecls decls -> BDecls <$> sugar decls

instance Sugar Rhs where
    sugar = \case
        UnGuardedRhs exp -> UnGuardedRhs <$> (expStripParen True <$> sugar exp)
        GuardedRhss rhss -> GuardedRhss  <$> sugar rhss

instance Sugar GuardedRhs where
    sugar (GuardedRhs srcLoc           stmts           exp)
        =  GuardedRhs srcLoc <$> sugar stmts <*> sugar exp

instance Sugar Stmt where
    sugar = \case
        Generator srcLoc pat exp -> Generator srcLoc pat <$> sugar exp
        Qualifier exp -> Qualifier <$> sugar exp
        LetStmt binds -> LetStmt <$> sugar binds
        RecStmt stmts -> RecStmt <$> sugar stmts

pattern App2 op x y = op `App` x `App` y

instance Sugar Exp where
    sugar = fmap expMatch . \case
        exp@Var{} -> return exp
        exp@Con{} -> return exp
        exp@Lit{} -> return exp
        List exps -> List <$> sugar exps
        Tuple boxed exps -> Tuple boxed <$> sugar exps
        Paren exp  -> Paren <$> sugar exp
        App x y -> App <$> sugar x <*> sugar y
        Lambda srcLoc pats exp -> Lambda srcLoc pats <$> sugar exp
        InfixApp x op y -> InfixApp <$> sugar x <*> pure op <*> sugar y
        RightSection op exp -> RightSection op <$> sugar exp
        Do stmts -> Do <$> sugar stmts
        exp -> error ("unsupported exp: " ++ show exp)

expMatch
    = expStripParen False
    . expMatchInfix
    . expJoinLambda
    . expJoinList
    . expAppSection
    . expDoMatch

expMatchInfix = \case
    App2 (Con op) x y -> case op of
        Special (TupleCon boxed _) -> Tuple boxed [x, y]
        _ -> Paren (InfixApp (Paren x) (QConOp op) (Paren y))
    App2 (Var op) x y -> Paren (InfixApp (Paren x) (QVarOp op) (Paren y))
    exp -> exp

expStripParen aggressive = \case
    Paren exp | (aggressive || expIsAtomic exp) -> exp
    exp -> exp

expJoinLambda = \case
    Lambda srcLoc pats (Lambda _ pats' exp) -> Lambda srcLoc (pats ++ pats') exp
    exp -> exp

expJoinList = \case
    List xs | Just cs <- charList xs -> Lit (String cs)
    InfixApp x (QConOp (Special Cons)) (List xs) -> List (x:xs)
    InfixApp (Lit (Char c)) (QConOp (Special Cons)) (Lit (String cs))
        -> Lit (String (c:cs))
    exp -> exp

charList = traverse $ \case
    Lit (Char c) -> Just c
    _ -> Nothing

expAppSection = \case
    App (RightSection (QVarOp op) y) x -> App2 (Var op) x y
    App (RightSection (QConOp op) y) x -> App2 (Con op) x y
    exp -> exp

expDoMatch = \case
    App2 (Var (UnQual (Symbol ">>="))) x (Lambda srcLoc [pat] a)
        -> Do [Generator srcLoc pat x, Qualifier a]
    Do [Qualifier exp] -> exp
    Do stmts -> Do (stmts >>= expandStmt) where
        expandStmt = \case
            Qualifier (Do stmts) -> stmts
            stmt -> [stmt]
    exp -> exp

expIsAtomic = \case
    Paren{} -> True
    Var{} -> True
    Con{} -> True
    Lit{} -> True
    List{} -> True
    _ -> False