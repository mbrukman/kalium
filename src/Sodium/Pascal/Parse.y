{
module Sodium.Pascal.Parse (parse, tokenize) where

import Control.Monad

import qualified Sodium.Pascal.Tokenize as T
import Sodium.Pascal.Program

import qualified Text.Parsec as P

}

%partial parser
%tokentype { T.Token   }
%error     { parseErr  }

%monad     { P.Parsec String ()  }
%lexer     { T.tokenCC } { T.EOF }

%token
    var      { T.KwVar   }
    begin    { T.KwBegin }
    end      { T.KwEnd   }
    for      { T.KwFor   }
    to       { T.KwTo    }
    do       { T.KwDo    }
    function { T.KwFunction }
    true     { T.KwTrue  }
    false    { T.KwFalse }
    and      { T.KwAnd   }
    or       { T.KwOr    }
    if       { T.KwIf    }
    then     { T.KwThen  }
    else     { T.KwElse  }
    case     { T.KwCase  }
    of       { T.KwOf    }
    '('      { T.LParen  }
    ')'      { T.RParen  }
    ';'      { T.Semicolon }
    ','      { T.Comma     }
    '.'      { T.Dot       }
    '..'     { T.DoubleDot }
    '+'      { T.Plus      }
    '-'      { T.Minus     }
    ':='     { T.Assign    }
    '*'      { T.Asterisk  }
    '/'      { T.Slash     }
    ':'      { T.Colon     }
    '='      { T.EqSign    }
    '<'      { T.Suck      }
    '>'      { T.Blow      }
    '['      { T.LSqBrace  }
    ']'      { T.RSqBrace  }
    name     { T.Name $$   }
    inumber  { T.INumber _    }
    fnumber  { T.FNumber _ _  }
    enumber  { T.ENumber _ _ _ _ }
    quote    { T.Quote $$  }
    unknown  { T.Unknown _ }

%%

Program : Funcs Vars Body '.' { Program (reverse $1) $2 $3 }

Funcs :            {      [] }
      | Funcs Func { $2 : $1 }

Vars  :              { [] }
      | var VarDecls { $2 }

VarDecls :                  {      [] }
         | VarDecls VarDecl { $2 : $1 }

VarDecl : VarNames ':' Type ';' { VarDecl $1 $3 }

VarNames :              name { $1 : [] }
         | VarNames ',' name { $3 : $1 }


Func : function name Params ':' Type ';' Vars Body ';'
     { Func     $2   $3         $5       $7   $8 }

Params :                    { [] }
       | '('            ')' { [] }
       | '(' ParamDecls ')' { $2 }

ParamDecls : ParamDecl                { $1 : [] }
           | ParamDecl ';' ParamDecls { $1 : $3 }

ParamDecl : ParamNames ':' Type { VarDecl (reverse $1) $3 }

ParamNames :                name { $1 : [] }
           | ParamNames ',' name { $3 : $1 }

Body : begin Statements end { reverse $2 }

Statements :                           {      [] }
           |                Statement  { $1 : [] }
           | Statements ';' Statement_ { $3 : $1 }

Statement_ : Statement  { $1 }
           |            { BodyStatement [] }

Statement  : AssignStatement  { $1 }
           | ExecuteStatement { $1 }
           | ForStatement     { $1 }
           | IfStatement      { $1 }
           | CaseStatement    { $1 }
           | Body             { BodyStatement $1 }


AssignStatement  : name ':=' Expression { Assign $1 $3 }

ExecuteStatement : name           { Execute $1 [] }
                 | name Arguments { Execute $1 $2 }

ForStatement : for      name ':=' Expression to Expression do Statement_
             { ForCycle $2        $4            $6            $8 }

IfStatement : if       Expression ThenClause ElseClause
            { IfBranch $2         $3         $4 }

ThenClause : then Statement_ { $2 }
ElseClause :                 { Nothing }
           | else Statement_ { Just $2 }

CaseStatement : case       Expression of CaseClauses  ElseClause end
              { CaseBranch $2            (reverse $4) $5 }

CaseClauses :                        {      [] }
            | CaseClauses CaseClause { $2 : $1 }

CaseClause : Ranges ':' Statement_ ';' { (reverse $1, $3) }

Ranges : Range            { $1 : [] }
       | Ranges ',' Range { $3 : $1 }

Range :                 Expression { $1 }
      | Expression '..' Expression { Binary OpRange $1 $3 }

{-
TODO:
    Expression
    Arguments
    Type
-}

Expression: name { Access $1 }
Arguments : '(' ')' { [] }
Type      : name { PasType $1 }

{
parseErr _ = mzero

parse = either (error.show) id . P.parse parser ""

tokenize :: String -> Either P.ParseError [T.Token]
tokenize = P.parse tokenizer "" where
    tokenizer = T.tokenCC cont
    cont T.EOF = return []
    cont token = (token:) `fmap` tokenizer
}
