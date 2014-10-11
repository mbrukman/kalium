module Sodium.Nucleus.Pass.ExtractBody (extractBody) where

import Control.Lens
import Control.Monad
import qualified Data.Map as M
import Sodium.Nucleus.Program.Vector
import Sodium.Nucleus.Recmap.Vector
import Sodium.Nucleus.Pattern
import Sodium.Util (tryApply)

extractBody :: Program -> Program
extractBody = over recmapped (tryApply bodyMatch)

bodyMatch :: Statement -> Maybe Statement
bodyMatch (BodyStatement body)
    | M.null (body ^. bodyVars) && null (body ^. bodyBinds)
        = return $ Assign (body ^. bodyResult)
    | otherwise = do
        -- TODO: propagate the bound variables
        -- onto the enclosing body
        guard $ M.null (body ^. bodyVars)
        [bind] <- return (body ^. bodyBinds)
        guard $ expMatch (bind ^. bindPattern) (body ^. bodyResult)
        return (bind ^. bindStatement)
bodyMatch _ = Nothing
