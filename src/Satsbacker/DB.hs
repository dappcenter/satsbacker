{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

module Satsbacker.DB
    ( migrate
    , openDb
    ) where

import Control.Monad (unless)
import Control.Monad.Logger
import Control.Monad.IO.Class
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Foldable (traverse_)
import Data.Text.Encoding (encodeUtf8)
import Database.SQLite.Simple
import System.Directory (createDirectoryIfMissing)

import qualified Data.ByteString as BS
import qualified Data.Text as T

import Bitcoin.Network

-- ensureDb :: FilePath -> IO ()
-- ensureDb dataPath = do

migrations :: [Query]
migrations = [
    "CREATE TABLE version (version INTEGER)",      -- 0
    "INSERT INTO version (version) VALUES (1)",    -- 1

    "CREATE TABLE users (id INTEGER PRIMARY KEY,\
     \ password TEXT, \
     \ email TEXT, \
     \ email_confirmed INTEGER, \
     \ name TEXT unique, \
     \ making TEXT, \
     \ created_at INTEGER NOT_NULL DEFAULT CURRENT_TIMESTAMP, \
     \ permissions INTEGER) ",    -- 2

     "CREATE TABLE invoices (invoice_id TEXT PRIMARY KEY,\
     \ tier_id INTEGER,\
     \ email TEXT,\
     \ payer_id INTEGER)", -- 3

     "CREATE TABLE tiers (id INTEGER PRIMARY KEY,\
     \ user_id INTEGER NOT NULL,\
     \ description TEXT,\
     \ quota INTEGER,\
     \ type INTEGER not null,\
     \ amount_fiat INTEGER,\
     \ amount_msats INTEGER,\
     \ created_at INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP,\
     \ state INTEGER)",        -- 4

     "CREATE TABLE subscriptions (id INTEGER PRIMARY KEY,\
     \ for_user INTEGER NOT NULL,\
     \ user_id INTEGER,\
     \ user_email TEXT,\
     \ user_cookie TEXT,\
     \ valid_until INTEGER NOT NULL,\
     \ tier_id INTEGER NOT NULL,\
     \ created_at INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP\
     \)", -- 5

     "CREATE TABLE payindex (payindex INTEGER)", -- 6
     "INSERT INTO payindex (payindex) VALUES (0)", -- 7

     "CREATE TABLE site (id INTERGER PRIMARY KEY,\
     \ name TEXT NOT NULL)", -- 8

     "INSERT INTO site (name) VALUES ('satsbacker')", -- 9

     "ALTER TABLE site ADD hostname TEXT", -- 10
     "UPDATE site set (hostname) = ('localhost')", -- 11
     "ALTER TABLE subscriptions ADD invoice_id TEXT", -- 12
     "ALTER TABLE site ADD amount_type TEXT" -- 13
  ]

hasVersionTable :: Connection -> IO Bool
hasVersionTable conn = do
  res <- query_ conn "SELECT name from sqlite_master WHERE type='table' and name='version'"
           :: IO [Only Text]
  return (not (null res))

getDbVersion :: Connection -> IO Int
getDbVersion conn = do
  hasVersion <- hasVersionTable conn
  if not hasVersion
    then return 0
    else do
      res <- fmap listToMaybe (query_ conn "SELECT version FROM version LIMIT 1")
      return (maybe 0 fromOnly res)

updateVersion :: Connection -> Int -> IO ()
updateVersion conn ver =
  execute conn "UPDATE version SET version = ?" (Only ver)

-- TODO: dev-only
saveMigration :: Int -> Int -> [Query] -> IO ()
saveMigration from to stmts = do
  createDirectoryIfMissing True ".migrations"
  let fileName = show from ++ "-to-" ++ show to ++ ".txt"
      contents = foldMap ((<>"\n") . fromQuery) stmts
  BS.writeFile (".migrations/" ++ fileName) (encodeUtf8 contents)


openDb :: (MonadIO m, MonadLogger m) => BitcoinNetwork -> m Connection
openDb network =
  let dbfile = case network of
                 Mainnet -> "satsbacker.db"
                 Testnet -> "satsbacker-testnet.db"
                 Regtest -> "satsbacker-regtest.db"
  in
    do logInfoN ("[db] using " <> dbfile)
       liftIO (open (T.unpack dbfile))


migrate :: Connection -> IO ()
migrate conn = do
  version <- getDbVersion conn
  let stmts          = drop version migrations
      latestVersion  = length migrations
  unless (null stmts) $ do
    if latestVersion < version then
      fail ("Refusing to migrate down from version "
              ++ show version ++ " to " ++ show latestVersion)
    else do
      withTransaction conn $ do
        traverse_ (execute_ conn) stmts
        updateVersion conn latestVersion
      saveMigration version latestVersion stmts
