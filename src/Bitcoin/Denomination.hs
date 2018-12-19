{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Bitcoin.Denomination
    ( Denomination(..)
    , MSats(..)
    , Sats(..)
    , Bits(..)
    , Btc(..)
    , bits, msats, sats, toBits, btc, toSats, toBtc
    , showBits
    ) where

import Data.Aeson
import Data.Int (Int64)
import Text.Printf

class Denomination a where
  toMsats :: a -> MSats
  -- fromMsats :: Int -> a
  -- numMsats :: Int

newtype MSats = MSats { getMsats :: Int64 }
  deriving (FromJSON, ToJSON, Num, Ord, Eq)

newtype Sats = Sats { getSats :: Rational }
  deriving (FromJSON, ToJSON, Num, Ord, Eq)

newtype Bits = Bits { getBits :: Rational }
  deriving (FromJSON, ToJSON, Num, Ord, Eq)

newtype Btc = Btc { getBtc :: Rational }
  deriving (FromJSON, ToJSON, Num, Ord, Eq)

instance Denomination MSats where
  toMsats a = a

bitsSize :: Num a => a
bitsSize = 100000

satsSize :: Num a => a
satsSize = 1000

btcSize :: Num a => a
btcSize = 100000000000

instance Denomination Bits where
  toMsats (Bits bitz) = msats (round (bitz * bitsSize))

instance Denomination Btc where
  toMsats (Btc btc_) = msats (round (btc_ * btcSize))

instance Denomination Sats where
  toMsats (Sats sats_) = msats (round (sats_ * 1000))

bits :: Rational -> Bits
bits = Bits

msats :: Int64 -> MSats
msats = MSats

sats :: Rational -> Sats
sats = Sats

btc :: Rational -> Btc
btc = Btc

toBits :: Denomination a => a -> Bits
toBits = Bits . (/ bitsSize) . toRational . getMsats . toMsats

toSats :: Denomination a => a -> Sats
toSats = Sats . (/ satsSize) . toRational . getMsats . toMsats

toBtc :: Denomination a => a -> Btc
toBtc = Btc . (/ btcSize) . toRational . getMsats . toMsats

instance Show MSats where
  show (MSats units) = printf "%d msats" units

instance Show Bits where
  show (Bits units) = printf "%s bits" (showRational 5 units)

instance Show Sats where
  show (Sats units) = printf "%s sats" (showRational 3 units)

instance Show Btc where
  show (Btc units) = printf "%s BTC" (showRational 3 units)

showBits :: Bits -> String
showBits (Bits units) =
    let
        b = showRational 5 units
    in
      reverse $
        case dropWhile (=='0') (reverse b) of
          '.' : rest -> rest
          xs -> xs


showRational :: Int -> Rational -> String
showRational n r =
    let d = round (abs r * 10^n)
        s = show (d :: Integer)
        s' = replicate (n - length s + 1) '0' ++ s
        (h, f) = splitAt (length s' - n) s'
    in  (if r < 0 then "-" else "") ++ h ++ "." ++ f
