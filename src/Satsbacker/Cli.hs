{-# LANGUAGE RecordWildCards #-}

module Satsbacker.Cli where

import Database.SQLite.Simple (Connection)
import Control.Concurrent.MVar (MVar, withMVar)
import System.Exit (exitFailure)
import Data.Text (Text)

import qualified Data.Text as T

import Satsbacker.Data.User
import Satsbacker.Data.Email
import Satsbacker.Server
import Satsbacker.Config
import Satsbacker.DB.Table (insert)

createUserUsage :: IO ()
createUserUsage = do
  putStrLn "usage: satsbacker create-user <name> <email> <password> [is-admin]"
  exitFailure


createUserCmd :: MVar Connection -> [Text] -> IO ()
createUserCmd mvconn args = do
  case args of
    (name:email:pass:adminArg) -> do
      user_ <- createUser (Plaintext pass)
      let isAdmin = not (null adminArg)
          user = user_ {
                    userName        = Username name
                  , userEmail       = Email email
                  , userPermissions = Permissions (if isAdmin then 1 else 0)
                  }
      userId <- withMVar mvconn $ \conn -> insert conn user
      putStrLn ("created " ++ (if isAdmin then "admin" else "normal")
                           ++ " user "
                           ++ ('\'' : T.unpack name) ++ "'"
                           ++ " <" ++ T.unpack email ++ ">"
                           ++ " (id:" ++ show userId ++ ")"
                           )
    _ -> createUserUsage


processArgs :: Config -> Text -> [Text] -> IO ()
processArgs cfg@Config{..} arg rest =
    case (arg, rest) of
      ("create-user", args) ->
          createUserCmd cfgConn args

      ("server", _) ->
          startServer cfg

      (_, _) ->
          usage


usage :: IO ()
usage = do
  putStrLn "usage: satsbacker <command>"
  putStrLn ""
  putStrLn "commands:"
  putStrLn ""
  putStrLn "  - create-user"
  putStrLn ""
  exitFailure

