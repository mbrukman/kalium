{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
module Kalium.Nucleus.Vector.Name where

import Kalium.Prelude
import Kalium.Util

import Control.Monad.Reader
import Control.Monad.Writer

import qualified Data.Set as S

import Kalium.Nucleus.Vector.Program

class Mentionable a where mentionable :: a -> Set Name
instance Mentionable (Set Name) where mentionable = id
instance Mentionable      Name  where mentionable = S.singleton

mentions :: (Mask a, Mentionable names) => a -> names -> Bool
a `mentions` names = getAny . execWriter
                 $ runReaderT (mask a) check
    where check name = do
            tell $ Any (name `S.member` mentionable names)
            return name

class Mask a where
    mask :: (Monad m) => a -> ReaderT (Name -> m Name) m a

instance (Mask a, Mask b) => Mask (a, b) where
    mask = _1 mask >=> _2 mask

instance (Mask a, Mask b, Mask c) => Mask (a, b, c) where
    mask = _1 mask >=> _2 mask >=> _3 mask

instance Mask a => Mask [a] where
    mask = traverse mask

instance Mask Name where
    mask name = do
        k <- ask
        lift (k name)

instance Mask Type where
    -- no user-defined types yet
    mask = return

instance Mask Pattern where
    mask  =  \case
        PAccess name ty -> PAccess <$> mask name <*> mask ty
        PTuple  p1   p2 -> PTuple  <$> mask p1   <*> mask p2
        PWildCard -> return PWildCard
        PUnit     -> return PUnit
        PExt pext -> absurd pext

instance Mask Expression where
    mask  = \case
        Lambda pat a -> Lambda <$> mask pat <*> mask a
        Beta a1 a2 -> Beta <$> mask a1 <*> mask a2
        Primary lit -> return (Primary lit)
        Access name -> Access <$> mask name
        Ext ext -> absurd ext

instance Mask Func where
    mask  =  funcType mask
         >=> funcExpression mask

instance Mask Program where
    mask  =  (programFuncs . mAsList) mask
