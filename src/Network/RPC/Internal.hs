{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-unused-do-bind #-}

{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Network.RPC.Internal
    ( sockRequest
    ) where

import Data.ByteString
import System.IO.Unsafe (unsafeInterleaveIO)
import Control.Monad.IO.Class (MonadIO(..))
import Data.Maybe (fromMaybe)
import Network.RPC.Common (defaultTimeout)
import Network.RPC.Config (SocketConfig(..))
import Network.RPC.Error
import Network.Socket.ByteString
import Network.Socket (socket, Family(AF_UNIX), SocketType(Stream), connect, shutdown,
                       SockAddr(SockAddrUnix), close, ShutdownCmd(ShutdownReceive))

import qualified Data.ByteString as BS
import qualified Data.DList as DL
import qualified Data.ByteString.Lazy as Lazy


openCloseSum :: BS.ByteString -> Int
openCloseSum = BS.foldl counter 0
  where
    counter n 123 = n + 1 -- {
    counter n 125 = n - 1 -- }
    counter n _   = n


-- this isn't a generic socket request reader, it counts open an closing brackets
-- to make sure it doesn't call recv too many times...
sockRequest :: MonadIO m => SocketConfig -> ByteString -> m (Either RPCError Lazy.ByteString)
sockRequest SocketConfig{..} bs = liftIO $ timeout tout $ do
  soc <- socket AF_UNIX Stream 0
  catching connectionError (connect soc (SockAddrUnix rpcPath))
  catching writeError (sendAll soc bs)
  catching readError (readAll soc)
  where
    tout        = fromMaybe defaultTimeout rpcTimeout
    readAll soc = fmap Lazy.fromChunks (readChunks soc 0)

    readChunks soc open = unsafeInterleaveIO $ do
        chunk <- recv soc 4096
        let count = open + openCloseSum chunk
        if count == 0 || BS.null chunk
          then shutdown soc ShutdownReceive >> return [chunk]
          else fmap (chunk :) (readChunks soc count)