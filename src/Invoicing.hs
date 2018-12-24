{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}

module Invoicing
    ( invoiceRoutes
    , newInvoice
    , waitInvoices
    ) where

import Control.Applicative (optional)
import Control.Monad.IO.Class (liftIO)
import Control.Concurrent (MVar, takeMVar)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8)
import Network.HTTP.Types (status402)
import Network.RPC.Config (SocketConfig(..))
import System.Timeout (timeout)
import Web.Scotty

import qualified Data.Text as T
import qualified Data.ByteString.Char8 as B8

import Bitsbacker.InvoiceId (newInvoiceId, encodeInvoiceId)
import Bitsbacker.Data.Invoice
import Bitsbacker.Config

import Bitcoin.Denomination


import Network.RPC (rpc)

newInvoice :: SocketConfig -> MSats -> Text -> IO Invoice
newInvoice cfg (MSats int) description = do
  invId <- liftIO newInvoiceId
  let label = encodeInvoiceId invId
      args  = [show int, B8.unpack label, T.unpack description]
  newInv <- rpc cfg "invoice" args
  let inv = fromNewInvoice (decodeUtf8 label) newInv
  either fail return inv

postInvoice :: Config -> ActionM ()
postInvoice Config{..} = do
  msatoshis   <- msats <$> param "msatoshi"
  description <-           param "description"
  inv <- liftIO (newInvoice cfgRPC msatoshis description)
  json inv


micro :: Int
micro = 1000000

-- max 30 minutes
sanitizeTimeout :: Int -> Int
sanitizeTimeout = min (1800 * micro) . (*micro)


waitForInvoice :: MVar WaitInvoice -> Text -> IO Invoice
waitForInvoice !mv !invId = do
  WaitInvoice (!_, !(CLInvoice !inv)) <- takeMVar mv
  if (invoiceId inv == invId)
     then return inv
     else waitForInvoice mv invId


waitInvoice :: Config -> ActionM ()
waitInvoice Config{..} = do
  mtimeout <- optional (param "timeout")
  invId <- param "invId"
  -- default 30 second timeout
  let waitFor = maybe (30 * micro) sanitizeTimeout mtimeout
  minv <- liftIO $ timeout waitFor $ waitForInvoice cfgPayNotify invId
  case minv of
    Nothing  -> status status402
    Just inv -> json inv


invoiceRoutes :: Config -> ScottyM ()
invoiceRoutes cfg = do
  post "/invoice" (postInvoice cfg)
  get "/invoice/:invId/wait" (waitInvoice cfg)
