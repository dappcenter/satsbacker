{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Satsbacker.Config where

import Control.Concurrent.MVar
import Control.Concurrent (forkIO)
import Control.Exception (SomeException, try)
import Data.Functor (void)
import Data.Text (Text)
import Data.Maybe (fromMaybe, isJust)
import Database.SQLite.Simple (Connection, execute, query_, Only(..))
import Network.RPC (rpc)
import System.Environment (lookupEnv)
import System.Timeout (timeout)
import Data.Aeson
import Data.Aeson.Types
import Data.List.NonEmpty (NonEmpty)

import Bitcoin.Network
import Satsbacker.DB
import Satsbacker.Logging
import Satsbacker.Data.Invoice

import Network.RPC

import Network.RPC.Config (SocketConfig(..))

import qualified Data.HashMap.Lazy as Map
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T

data Config = Config {
      cfgConn      :: MVar Connection
    , cfgRPC       :: SocketConfig
    , cfgPayNotify :: MVar WaitInvoice
    , cfgLnConfig  :: LightningConfig
    }

cfgNetwork :: Config -> BitcoinNetwork
cfgNetwork = lncfgNetwork . cfgLnConfig

data PeerAddr = PeerAddr {
      peerAddrType :: Text
    , peerAddr     :: Text
    , peerAddrPort :: Int
    }

instance FromJSON PeerAddr where
    parseJSON (Object obj) =
        PeerAddr <$> obj .: "type"
                 <*> obj .: "address"
                 <*> obj .: "port"
    parseJSON _ = fail "expected object for PeerAddr"


data LightningConfig = LightningConfig {
      lncfgNetwork  :: BitcoinNetwork
    , lncfgPeerId   :: Text
    , lncfgPeerAddr :: NonEmpty PeerAddr
    }

instance FromJSON LightningConfig where
    parseJSON v@(Object obj) =
        LightningConfig <$> parseNetworkValue v
                        <*> obj .: "id"
                        <*> obj .: "address"
    parseJSON _ = fail "could not parse clightning getinfo config"

instance ToJSON Config where
    toJSON cfg@Config{..} =
        let network = cfgNetwork cfg
        in
          object
            [ "network"    .= network
            , "is_testnet" .= (network == Testnet)
            , "peer"       .= showLnPeer cfgLnConfig
            ]


showLnPeer :: LightningConfig -> Text
showLnPeer LightningConfig{..} =
    showPeer (NE.head lncfgPeerAddr) lncfgPeerId
        
showPeer :: PeerAddr -> Text -> Text
showPeer PeerAddr{..} peerId =
    if peerAddrPort == 9735
       then peerId <> "@" <> peerAddr
       else peerId <> "@" <> peerAddr <> ":" <> T.pack (show peerAddrPort)


getPayIndex :: Connection -> IO Int
getPayIndex conn =
  fromOnly . head <$> query_ conn "SELECT payindex FROM payindex"


persistPayIndex :: Connection -> Int -> IO ()
persistPayIndex conn payind =
  execute conn "UPDATE payindex SET payindex = ?" (Only payind)


waitInvoices :: Int -> Int -> Config -> IO ()
waitInvoices 10 _ _ = fail "Too many errors when waiting for payments"
waitInvoices !errs !payindex !cfg@Config{..} = do
  ewi :: Either SomeException WaitInvoice <-
           try $ rpc cfgRPC "waitanyinvoice" [payindex]
  case ewi of
    Left err -> logError (show err) >> waitInvoices (errs + 1) payindex cfg
    Right !wi@(WaitInvoice (!index, !_inv)) -> do
      isEmpty <- isEmptyMVar cfgPayNotify
      if isEmpty
        then putMVar cfgPayNotify wi
        else void (swapMVar cfgPayNotify wi)
      print wi
      withMVar cfgConn $ \conn -> persistPayIndex conn index
      waitInvoices 0 index cfg


getLightningConfig :: SocketConfig -> IO LightningConfig
getLightningConfig cfg = do
  mlncfg <- timeout (5 * 1000000) (rpc_ cfg "getinfo")
  lncfg <- maybe timeouterr return mlncfg
  logError $ "[ln] using peer " ++ T.unpack (showLnPeer lncfg)
  return lncfg
  where
    timeouterr = fail "timeout during clightning getinfo call"


parseNetworkValue :: Value -> Parser BitcoinNetwork
parseNetworkValue = either fail return . getNetwork

getNetwork :: Value -> Either String BitcoinNetwork
getNetwork val = do
  network <- key "network" val
  maybe err return (parseNetwork network)
  where
    err = Left "getinfo: network key not found"
    key str (Object obj) =
      case Map.lookup str obj of
        Just (String txt) -> return txt
        Just _            -> err
        Nothing           -> err
    key _ _ = err

getConfig :: IO Config
getConfig = do
  socketCfg <- getSocketConfig
  lncfg <- getLightningConfig socketCfg
  logError $ "[ln] detected Bitcoin " ++ show (lncfgNetwork lncfg)
                 ++ " from clightning"
  conn <- openDb (lncfgNetwork lncfg)
  migrate conn
  payindex <- getPayIndex conn
  mvconn <- newMVar conn
  mvnotify <- newEmptyMVar
  let cfg = Config mvconn socketCfg mvnotify lncfg
  _ <- forkIO (waitInvoices 0 payindex cfg)
  return cfg


getSocketConfig :: IO SocketConfig
getSocketConfig = do
  path <- getRPCSocket
  return (SocketConfig path Nothing)


getRPCSocket :: IO FilePath
getRPCSocket = do
  mstrsocket <- lookupEnv "RPCSOCK"
  let from = if isJust mstrsocket
               then "RPCSOCK env"
               else "default setting"
      cfg = fromMaybe "/home/jb55/.lightning-bitcoin-rpc" mstrsocket
  logError $ "[rpc] using " ++ cfg  ++ " from " ++ from
  return cfg