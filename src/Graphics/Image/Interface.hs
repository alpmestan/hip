{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
#if __GLASGOW_HASKELL__ >= 800
    {-# OPTIONS_GHC -Wno-redundant-constraints #-}
    {-# LANGUAGE UndecidableSuperClasses #-}
#endif
{-# LANGUAGE ViewPatterns #-}
-- |
-- Module      : Graphics.Image.Interface
-- Copyright   : (c) Alexey Kuleshevich 2017
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Graphics.Image.Interface (
  Pixel, ColorSpace(..), AlphaSpace(..), Elevator(..),
  BaseArray(..), Array(..), MArray(..),
  Exchangable(..), exchangeFrom, exchangeThrough,
  defaultIndex, borderIndex, maybeIndex, Border(..), handleBorderIndex,
  fromIx, toIx, checkDims
#if !MIN_VERSION_base(4,8,0)
  , module Control.Applicative
  , Foldable
#endif
  ) where

import Prelude hiding (and, map, zipWith, sum, product)
#if !MIN_VERSION_base(4,8,0)
import Control.Applicative
#endif
import Data.Maybe (fromMaybe)
import Data.Foldable
import GHC.Exts (Constraint)
import Data.Typeable (Typeable, showsTypeRep, typeOf)
import Control.DeepSeq (NFData(rnf), deepseq)
import Data.Word

import Control.Monad.Primitive (PrimMonad (..))


-- | A Pixel family with a color space and a precision of elements.
data family Pixel cs e :: *


class (Eq cs, Enum cs, Show cs, Bounded cs, Typeable cs, Elevator e, Typeable e)
      => ColorSpace cs e where
  
  type Components cs e

  -- | Convert a Pixel to a representation suitable for storage as an unboxed
  -- element, usually a tuple of channels.
  toComponents :: Pixel cs e -> Components cs e

  -- | Convert from an elemnt representation back to a Pixel.
  fromComponents :: Components cs e -> Pixel cs e

  -- | Construt a Pixel by replicating the same value across all of the components.
  promote :: e -> Pixel cs e

  -- | Retrieve Pixel's component value
  getPxC :: Pixel cs e -> cs -> e
  
  -- | Set Pixel's component value
  setPxC :: Pixel cs e -> cs -> e -> Pixel cs e
  
  -- | Map a channel aware function over all Pixel's components.
  mapPxC :: (cs -> e -> e) -> Pixel cs e -> Pixel cs e 

  -- | Map a function over all Pixel's componenets.
  liftPx :: (e -> e) -> Pixel cs e -> Pixel cs e

  -- | Zip two Pixels with a function.
  liftPx2 :: (e -> e -> e) -> Pixel cs e -> Pixel cs e -> Pixel cs e

  foldlPx2 :: (b -> e -> e -> b) -> b -> Pixel cs e -> Pixel cs e -> b

  -- | Right fold over all Pixel's components.
  foldrPx :: (e -> b -> b) -> b -> Pixel cs e -> b
  foldrPx f !z0 !xs = foldlPx f' id xs z0
      where f' k x !z = k $! f x z

  -- | Left strict fold over all Pixel's components.
  foldlPx :: (b -> e -> b) -> b -> Pixel cs e -> b
  foldlPx f !z0 !xs = foldrPx f' id xs z0
      where f' x k !z = k $! f z x

  foldl1Px :: (e -> e -> e) -> Pixel cs e -> e
  foldl1Px f !xs = fromMaybe (error "foldl1Px: empty Pixel")
                  (foldlPx mf Nothing xs)
      where
        mf m !y = Just (case m of
                           Nothing -> y
                           Just x  -> f x y)
  toListPx :: Pixel cs e -> [e]
  toListPx !px = foldr' f [] (enumFrom (toEnum 0))
    where f !cs !ls = getPxC px cs:ls

  

-- | A color space that supports transparency.
class (ColorSpace (Opaque cs) e, ColorSpace cs e) => AlphaSpace cs e where
  -- | A corresponding opaque version of this color space.
  type Opaque cs

  -- | Get an alpha channel of a transparant pixel. 
  getAlpha :: Pixel cs e -> e

  -- | Add an alpha channel of an opaque pixel.
  --
  -- @ addAlpha 0 (PixelHSI 1 2 3) == PixelHSIA 1 2 3 0 @
  addAlpha :: e -> Pixel (Opaque cs) e -> Pixel cs e
  
  -- | Convert a transparent pixel to an opaque one by dropping the alpha
  -- channel.
  --
  -- @ dropAlpha (PixelRGBA 1 2 3 4) == PixelRGB 1 2 3 @
  --
  dropAlpha :: Pixel cs e -> Pixel (Opaque cs) e


-- | A class with a set of convenient functions that allow for changing precision of
-- channels within pixels, while scaling the values to keep them in an appropriate range.
--
-- >>> let rgb = PixelRGB 0.0 0.5 1.0 :: Pixel RGB Double
-- >>> toWord8 rgb
-- <RGB:(0|128|255)>
--
class Elevator e where

  -- | Values are scaled to @[0, 255]@ range.
  toWord8 :: e -> Word8

  -- | Values are scaled to @[0, 65535]@ range.
  toWord16 :: e -> Word16

  -- | Values are scaled to @[0, 4294967295]@ range.
  toWord32 :: e -> Word32

  -- | Values are scaled to @[0, 18446744073709551615]@ range.
  toWord64 :: e -> Word64

  -- | Values are scaled to @[0.0, 1.0]@ range.
  toFloat :: e -> Float

  -- | Values are scaled to @[0.0, 1.0]@ range.
  toDouble :: e -> Double

  -- | Values are scaled from @[0.0, 1.0]@ range.
  fromDouble :: Double -> e


-- | Base array like representation for an image.
class (Show arr, ColorSpace cs e, Num (Pixel cs e),
       SuperClass arr cs e) =>
      BaseArray arr cs e where

  -- | Required array specific constraints for an array element.
  type SuperClass arr cs e :: Constraint
  type SuperClass arr cs e = ()

  -- | Underlying image representation.
  data Image arr cs e

  -- | Get dimensions of an image.
  --
  -- >>> frog <- readImageRGB VU "images/frog.jpg"
  -- >>> frog
  -- <Image VectorUnboxed RGB (Double): 200x320>
  -- >>> dims frog
  -- (200,320)
  --
  dims :: Image arr cs e -> (Int, Int)

class (MArray (Manifest arr) cs e, BaseArray arr cs e) => Array arr cs e where

  type Manifest arr :: *
  

  -- | Create an Image by supplying it's dimensions and a pixel generating
  -- function.
  makeImage :: (Int, Int) -- ^ (@m@ rows, @n@ columns) - dimensions of a new image.
            -> ((Int, Int) -> Pixel cs e)
               -- ^ A function that takes (@i@-th row, and @j@-th column) as an
               -- argument and returns a pixel for that location.
            -> Image arr cs e

  makeImageWindowed :: (Int, Int) -- ^ (@m@ rows, @n@ columns) - dimensions of a new image.
                    -> ((Int, Int), (Int, Int))
                    -> ((Int, Int) -> Pixel cs e)
                       -- ^ Function that generates inner pixels.
                    -> ((Int, Int) -> Pixel cs e)
                       -- ^ Function that generates border pixels
                    -> Image arr cs e

  -- | Create a scalar image, required for various operations on images with
  -- a scalar.
  scalar :: Pixel cs e -> Image arr cs e

  -- | Retrieves a pixel at @(0, 0)@ index. Useful together with `fold`, when
  -- arbitrary initial pixel is needed.
  index00 :: Image arr cs e -> Pixel cs e

  -- | Map a function over a an image.
  map :: Array arr cs' e' =>
         (Pixel cs' e' -> Pixel cs e)
         -- ^ A function that takes a pixel of a source image and returns a pixel
         -- for the result image a the same location.
      -> Image arr cs' e' -- ^ Source image.
      -> Image arr cs e   -- ^ Result image.

  -- | Map an index aware function over each pixel in an image.
  imap :: Array arr cs' e' =>
          ((Int, Int) -> Pixel cs' e' -> Pixel cs e)
        -- ^ A function that takes an index @(i, j)@, a pixel at that location
        -- and returns a new pixel at the same location for the result image.
       -> Image arr cs' e' -- ^ Source image.
       -> Image arr cs e   -- ^ Result image.

  -- | Zip two images with a function
  zipWith :: (Array arr cs1 e1, Array arr cs2 e2) =>
             (Pixel cs1 e1 -> Pixel cs2 e2 -> Pixel cs e)
          -> Image arr cs1 e1 -> Image arr cs2 e2 -> Image arr cs e

  -- | Zip two images with an index aware function
  izipWith :: (Array arr cs1 e1, Array arr cs2 e2) =>
              ((Int, Int) -> Pixel cs1 e1 -> Pixel cs2 e2 -> Pixel cs e)
           -> Image arr cs1 e1 -> Image arr cs2 e2 -> Image arr cs e

  -- | Traverse an image
  traverse :: Array arr cs' e' =>
              Image arr cs' e' -- ^ Source image.
           -> ((Int, Int) -> (Int, Int))
           -- ^ Function that takes dimensions of a source image and returns
           -- dimensions of a new image.
           -> (((Int, Int) -> Pixel cs' e') ->
               (Int, Int) -> Pixel cs e)
           -- ^ Function that receives a pixel getter (a source image index
           -- function), a location @(i, j)@ in a new image and returns a pixel
           -- for that location.
           -> Image arr cs e
  
  -- | Traverse two images.
  traverse2 :: (Array arr cs1 e1, Array arr cs2 e2) =>
               Image arr cs1 e1 -- ^ First source image.
            -> Image arr cs2 e2 -- ^ Second source image.
            -> ((Int, Int) -> (Int, Int) -> (Int, Int))
            -- ^ Function that produces dimensions for the new image.
            -> (((Int, Int) -> Pixel cs1 e1) ->
                ((Int, Int) -> Pixel cs2 e2) ->
                (Int, Int) -> Pixel cs e)
            -- ^ Function that produces pixels for the new image.
            -> Image arr cs e
  
  -- | Transpose an image
  transpose :: Image arr cs e -> Image arr cs e

  -- | Backwards permutation of an image. 
  backpermute :: (Int, Int) -- ^ Dimensions of a result image.
              -> ((Int, Int) -> (Int, Int))
                 -- ^ Function that maps an index of a source image to an index
                 -- of a result image.
              -> Image arr cs e -- ^ Source image.
              -> Image arr cs e -- ^ Result image.

  -- | Construct an image from a nested rectangular shaped list of pixels.
  -- Length of an outer list will constitute @m@ rows, while the length of inner lists -
  -- @n@ columns. All of the inner lists must be the same length and greater than @0@.
  --
  -- >>> fromLists [[PixelY (fromIntegral (i*j) / 60000) | j <- [1..300]] | i <- [1..200]]
  -- <Image VectorUnboxed Y (Double): 200x300>
  --
  -- <<images/grad_fromLists.png>>
  --
  fromLists :: [[Pixel cs e]]
            -> Image arr cs e

  -- | Perform matrix multiplication on two images. Inner dimensions must agree.
  (|*|) :: Image arr cs e -> Image arr cs e -> Image arr cs e

  -- | Undirected reduction of an image. 
  fold :: (Pixel cs e -> Pixel cs e -> Pixel cs e) -- ^ An associative folding function.
       -> Pixel cs e -- ^ Initial element, that is neutral with respect to the folding function.
       -> Image arr cs e -- ^ Source image.
       -> Pixel cs e

  -- | Undirected reduction of an image with an index aware function.
  foldIx :: (Pixel cs e -> (Int, Int) -> Pixel cs e -> Pixel cs e)
            -- ^ Function that takes an accumulator, index, a pixel at that
            -- index and returns a new accumulator pixel.
         -> Pixel cs e -- ^ Initial element, that is neutral with respect to the folding function.
         -> Image arr cs e -- ^ Source image.
         -> Pixel cs e

  -- | Pixelwise equality function of two images. Images are
  -- considered distinct if either images' dimensions or at least one pair of
  -- corresponding pixels are not the same. Used in defining an in instance for
  -- the 'Eq' typeclass.
  eq :: Eq (Pixel cs e) => Image arr cs e -> Image arr cs e -> Bool

  compute :: Image arr cs e -> Image arr cs e

  toManifest :: Image arr cs e -> Image (Manifest arr) cs e
  

-- | Array representation that is actually has real data stored in memory, hence
-- allowing for image indexing, forcing pixels into computed state etc.
class BaseArray arr cs e => MArray arr cs e  where
  data MImage s arr cs e

  unsafeIndex :: Image arr cs e -> (Int, Int) -> Pixel cs e
  
  -- | Get a pixel at @i@-th and @j@-th location.
  --
  -- >>> let grad_gray = makeImage (200, 200) (\(i, j) -> PixelY $ fromIntegral (i*j)) / (200*200)
  -- >>> index grad_gray (20, 30) == PixelY ((20*30) / (200*200))
  -- True
  --
  index :: Image arr cs e -> (Int, Int) -> Pixel cs e
  index !img !ix = borderIndex (error $ show img ++ " - Index out of bounds: " ++ show ix) img ix
  {-# INLINE index #-}

  -- | Make sure that an image is fully evaluated.
  deepSeqImage :: Image arr cs e -> a -> a

  -- | Fold an image from the left in a row major order.
  foldl :: (a -> Pixel cs e -> a) -> a -> Image arr cs e -> a

  -- | Fold an image from the right in a row major order.
  foldr :: (Pixel cs e -> a -> a) -> a -> Image arr cs e -> a

  -- | Create an Image by supplying it's dimensions and a monadic pixel
  -- generating action.
  makeImageM :: (Functor m, Monad m) =>
                (Int, Int) -- ^ (@m@ rows, @n@ columns) - dimensions of a new image.
             -> ((Int, Int) -> m (Pixel cs e))
                -- ^ A function that takes (@i@-th row, and @j@-th column) as an
                -- argument and generates a pixel for that location.
             -> m (Image arr cs e)

  -- | Monading mapping over an image.
  mapM :: (MArray arr cs' e', Functor m, Monad m) =>
          (Pixel cs' e' -> m (Pixel cs e)) -> Image arr cs' e' -> m (Image arr cs e)

  -- | Monading mapping over an image. Result is discarded.
  mapM_ :: (Functor m, Monad m) => (Pixel cs e -> m b) -> Image arr cs e -> m ()

  -- | Monadic folding.
  foldM :: (Functor m, Monad m) => (a -> Pixel cs e -> m a) -> a -> Image arr cs e -> m a

  -- | Monadic folding. Result is discarded.
  foldM_ :: (Functor m, Monad m) => (a -> Pixel cs e -> m a) -> a -> Image arr cs e -> m ()

  -- | Get dimensions of a mutable image.
  mdims :: MImage s arr cs e -> (Int, Int)

  -- | Yield a mutable copy of an image.
  thaw :: (Functor m, PrimMonad m) =>
          Image arr cs e -> m (MImage (PrimState m) arr cs e)

  -- | Yield an immutable copy of an image.
  freeze :: (Functor m, PrimMonad m) =>
            MImage (PrimState m) arr cs e -> m (Image arr cs e)

  -- | Create a mutable image with given dimensions. Pixels are likely uninitialized.
  new :: (Functor m, PrimMonad m) =>
         (Int, Int) -> m (MImage (PrimState m) arr cs e)

  -- | Yield the pixel at a given location.
  read :: (Functor m, PrimMonad m) =>
          MImage (PrimState m) arr cs e -> (Int, Int) -> m (Pixel cs e)

  -- | Set a pixel at a given location.
  write :: (Functor m, PrimMonad m) =>
           MImage (PrimState m) arr cs e -> (Int, Int) -> Pixel cs e -> m ()

  -- | Swap pixels at given locations.
  swap :: (Functor m, PrimMonad m) =>
          MImage (PrimState m) arr cs e -> (Int, Int) -> (Int, Int) -> m ()


-- | Allows for changing an underlying image representation.
class Exchangable arr' arr where

  -- | Exchange the underlying array representation of an image.
  exchange :: (Array arr' cs e, Array arr cs e) =>
              arr -- ^ New representation of an image.
           -> Image arr' cs e -- ^ Source image.
           -> Image arr cs e

-- | Changing to the same array representation as before is disabled and `exchange`
-- will behave simply as an identitity function.
instance Exchangable arr arr where

  exchange _ !img = img
  {-# INLINE exchange #-}


-- | `exchange` function that allows restricting representation type of the
-- source image.
exchangeFrom :: (Exchangable arr' arr, Array arr' cs e, Array arr cs e) =>
                arr'
             -> arr -- ^ New representation of an image.
             -> Image arr' cs e -- ^ Source image.
             -> Image arr cs e
exchangeFrom _ to !img = exchange to img
{-# INLINE exchangeFrom #-}


-- | `exchange` an image representation through an intermediate one.
exchangeThrough :: (Exchangable arr2 arr1, Exchangable arr1 arr,
                    Array arr2 cs e, Array arr1 cs e, Array arr cs e) =>
                arr1
             -> arr -- ^ New representation of an image.
             -> Image arr2 cs e -- ^ Source image.
             -> Image arr cs e
exchangeThrough through to = exchange to . exchange through
{-# INLINE exchangeThrough #-}


-- | Approach to be used near the borders during various transformations.
-- Whenever a function needs information not only about a pixel of interest, but
-- also about it's neighbours, it will go out of bounds around the image edges,
-- hence is this set of approaches that can be used in such situtation.
data Border px =
  Fill !px    -- ^ Fill in a constant pixel.
              --
              -- @
              --            outside |  Image  | outside
              -- ('Fill' 0) : 0 0 0 0 | 1 2 3 4 | 0 0 0 0
              -- @
              --
  | Wrap      -- ^ Wrap around from the opposite border of the image.
              --
              -- @
              --            outside |  Image  | outside
              -- 'Wrap' :     1 2 3 4 | 1 2 3 4 | 1 2 3 4
              -- @
              --
  | Edge      -- ^ Replicate the pixel at the edge.
              --
              -- @
              --            outside |  Image  | outside
              -- 'Edge' :     1 1 1 1 | 1 2 3 4 | 4 4 4 4
              -- @
              --
  | Reflect   -- ^ Mirror like reflection.
              --
              -- @
              --            outside |  Image  | outside
              -- 'Reflect' :  4 3 2 1 | 1 2 3 4 | 4 3 2 1
              -- @
              --
  | Continue  -- ^ Also mirror like reflection, but without repeating the edge pixel.
              --
              -- @
              --            outside |  Image  | outside
              -- 'Continue' : 1 4 3 2 | 1 2 3 4 | 3 2 1 4
              -- @
              --
  deriving Show

-- handleBorderIndex' :: Border px -- ^ Border handling strategy.
--                   -> (Int, Int) -- ^ Image dimensions
--                   -> ((Int, Int) -> px) -- ^ Image's indexing function.
--                   -> (Int, Int) -- ^ @(i, j)@ location of a pixel lookup.
--                   -> px
-- handleBorderIndex' border !(m, n) !getPx !(i, j) =
--   if i >= 0 && j >= 0 && i < m && j < n then getPx (i, j) else getPxB border where
--     getPxB (Fill px) = px
--     getPxB Wrap      = getPx (i `mod` m, j `mod` n)
--     getPxB Edge      = getPx (if i < 0 then 0 else if i >= m then m - 1 else i,
--                               if j < 0 then 0 else if j >= n then n - 1 else j)
--     getPxB Reflect   = getPx (if i < 0 then (abs i - 1) `mod` m else
--                                 if i >= m then (m - (i - m + 1)) `mod` m else i,
--                               if j < 0 then (abs j - 1) `mod` n else
--                                 if j >= n then (n - (j - n + 1)) `mod` n else j)
--     getPxB Continue  = getPx (if i < 0 then abs i `mod` m else
--                                 if i >= m then (m - (i - m + 2)) `mod` m else i,
--                               if j < 0 then abs j `mod` n else
--                                 if j >= n then (n - (j - n + 2)) `mod` n else j)
--     {-# INLINE getPxB #-}
-- {-# INLINE handleBorderIndex' #-}




-- | Border handling function. If @(i, j)@ location is within bounds, then supplied
-- lookup function will be used, otherwise it will be handled according to a
-- supplied border strategy.
handleBorderIndex :: Border px -- ^ Border handling strategy.
                   -> (Int, Int) -- ^ Image dimensions
                   -> ((Int, Int) -> px) -- ^ Image's indexing function.
                   -> (Int, Int) -- ^ @(i, j)@ location of a pixel lookup.
                   -> px
handleBorderIndex border !(m, n) !getPx !(i, j) =
  if north || east || south || west
  then case border of
    Fill px  -> px
    Wrap     -> getPx (i `mod` m, j `mod` n)
    Edge     -> getPx (if north then 0 else if south then m - 1 else i,
                       if west then 0 else if east then n - 1 else j)
    Reflect  -> getPx (if north then (abs i - 1) `mod` m else
                         if south then (-i - 1) `mod` m else i,
                       if west then (abs j - 1) `mod` n else
                         if east then (-j - 1) `mod` n else j)
    Continue -> getPx (if north then abs i `mod` m else
                         if south then (-i - 2) `mod` m else i,
                       if west then abs j `mod` n else
                         if east then (-j - 2) `mod` n else j)
    -- Reflect  -> getPx (if north then (abs i - 1) `mod` m else
    --                      if south then (m - (i - m + 1)) `mod` m else i,
    --                    if west then (abs j - 1) `mod` n else
    --                      if east then (n - (j - n + 1)) `mod` n else j)
    -- Continue -> getPx (if north then abs i `mod` m else
    --                      if south then (m - (i - m + 2)) `mod` m else i,
    --                    if west then abs j `mod` n else
    --                      if east then (n - (j - n + 2)) `mod` n else j)
  else getPx (i, j)
  where
    north = i < 0
    {-# INLINE north #-}
    south = i >= m
    {-# INLINE south #-}
    west = j < 0
    {-# INLINE west #-}
    east = j >= n
    {-# INLINE east #-}
{-# INLINE handleBorderIndex #-}



-- handleBorderIndex' border !(m, n) getPx !(i, j) =
--   case (i < 0, i >= m, j < 0, j >= n) of
--     (False, False, False, False) -> getPx (i, j)
--     (False, False, False,  True) ->
--       case border of
--         Fill px -> px
--         Wrap -> getPx (i, j `mod` n)
--         Edge -> getPx (i, n-1)
--         Reflect -> getPx (i, (n - (j - n + 1)) `mod` n)
--         Continue -> getPx (i, (n - (j - n + 2)) `mod` n)
--     (False, False, True,  False) ->
--       case border of
--         Fill px -> px
--         Wrap -> getPx (i, j `mod` n)
--         Edge -> getPx (i, 0)
--         Reflect -> getPx (i, (abs j - 1) `mod` n)
--         Continue -> getPx (i, abs j `mod` n)
--     (False, True, False,  False) ->
--       case border of
--         Fill px -> px
--         Wrap -> getPx (i, j `mod` n)
--         Edge -> getPx (i, 0)
--         Reflect -> getPx (i, (abs j - 1) `mod` n)
--         Continue -> getPx (i, abs j `mod` n)
    --((False, False, False,  True), Edge) -> getPx (i, j `mod` n)
      
  -- case (i >= 0, j >= 0, i < m, j < n) of
  --   (True, True, True, True) -> getPx (i, j)
  --   (True, True, True, True) -> getPx (i, j)
  --   then getPx (i, j) else getPxB border where



-- | Image indexing function that returns a default pixel if index is out of bounds.
defaultIndex :: MArray arr cs e =>
                Pixel cs e -> Image arr cs e -> (Int, Int) -> Pixel cs e
defaultIndex !px !img = handleBorderIndex (Fill px) (dims img) (index img)
{-# INLINE defaultIndex #-}


-- | Image indexing function that uses a special border resolutions strategy for
-- out of bounds pixels.
borderIndex :: MArray arr cs e =>
               Border (Pixel cs e) -> Image arr cs e -> (Int, Int) -> Pixel cs e
borderIndex atBorder !img = handleBorderIndex atBorder (dims img) (unsafeIndex img)
{-# INLINE borderIndex #-}


-- | Image indexing function that returns @'Nothing'@ if index is out of bounds,
-- @'Just' px@ otherwise.
maybeIndex :: MArray arr cs e =>
              Image arr cs e -> (Int, Int) -> Maybe (Pixel cs e)
maybeIndex !img@(dims -> (m, n)) !(i, j) =
  if i >= 0 && j >= 0 && i < m && j < n then Just $ index img (i, j) else Nothing
{-# INLINE maybeIndex #-}


-- | 2D to a flat vector index conversion.
--
-- __Note__: There is an implicit assumption that @j < n@
fromIx :: Int -- ^ @n@ columns
       -> (Int, Int) -- ^ @(i, j)@ row, column index
       -> Int -- ^ Flat vector index
fromIx !n !(i, j) = n * i + j
{-# INLINE fromIx #-}


-- | Flat vector to 2D index conversion.
toIx :: Int -- ^ @n@ columns
     -> Int -- ^ Flat vector index
     -> (Int, Int) -- ^ @(i, j)@ row, column index
toIx !n !k = divMod k n
{-# INLINE toIx #-}


checkDims :: String -> (Int, Int) -> (Int, Int)
checkDims err !ds@(m, n)
  | m <= 0 || n <= 0 = 
    error $
    show err ++ ": Image dimensions are expected to be positive: " ++ show ds
  | otherwise = ds
{-# INLINE checkDims #-}


instance (Applicative (Pixel cs), Bounded e) => Bounded (Pixel cs e) where
  maxBound = pure maxBound
  {-# INLINE maxBound #-}
  
  minBound = pure minBound
  {-# INLINE minBound #-}


instance (Foldable (Pixel cs), NFData e) => NFData (Pixel cs e) where

  rnf = foldr' deepseq ()
  {-# INLINE rnf #-}


instance (Array arr cs e, Eq (Pixel cs e)) => Eq (Image arr cs e) where
  (==) = eq
  {-# INLINE (==) #-}

  
instance Array arr cs e => Num (Image arr cs e) where
  (+)         = zipWith (+)
  {-# INLINE (+) #-}
  
  (-)         = zipWith (-)
  {-# INLINE (-) #-}
  
  (*)         = zipWith (*)
  {-# INLINE (*) #-}
  
  abs         = map abs
  {-# INLINE abs #-}
  
  signum      = map signum
  {-# INLINE signum #-}
  
  fromInteger = scalar . fromInteger
  {-# INLINE fromInteger #-}


instance (Fractional (Pixel cs e), Array arr cs e) =>
         Fractional (Image arr cs e) where
  (/)          = zipWith (/)
  {-# INLINE (/) #-}
  
  fromRational = scalar . fromRational 
  {-# INLINE fromRational #-}


instance (Floating (Pixel cs e), Array arr cs e) =>
         Floating (Image arr cs e) where
  pi    = scalar pi
  {-# INLINE pi #-}
  
  exp   = map exp
  {-# INLINE exp #-}
  
  log   = map log
  {-# INLINE log #-}
  
  sin   = map sin
  {-# INLINE sin #-}
  
  cos   = map cos
  {-# INLINE cos #-}
  
  asin  = map asin
  {-# INLINE asin #-}
  
  atan  = map atan
  {-# INLINE atan #-}
  
  acos  = map acos
  {-# INLINE acos #-}
  
  sinh  = map sinh
  {-# INLINE sinh #-}
  
  cosh  = map cosh
  {-# INLINE cosh #-}
  
  asinh = map asinh
  {-# INLINE asinh #-}
  
  atanh = map atanh
  {-# INLINE atanh #-}
  
  acosh = map acosh
  {-# INLINE acosh #-}  


instance MArray arr cs e => NFData (Image arr cs e) where
  rnf img = img `deepSeqImage` ()
  {-# INLINE rnf #-}



instance BaseArray arr cs e =>
         Show (Image arr cs e) where
  show (dims -> (m, n)) =
    "<Image " ++
    show (undefined :: arr) ++
    " " ++
    showsTypeRep (typeOf (undefined :: cs)) " (" ++
    showsTypeRep (typeOf (undefined :: e)) "): " ++
     show m ++ "x" ++ show n ++ ">"


instance MArray arr cs e =>
         Show (MImage st arr cs e) where
  show (mdims -> (m, n)) =
    "<MutableImage " ++
    show (undefined :: arr) ++
    " " ++
    showsTypeRep (typeOf (undefined :: cs)) " (" ++
    showsTypeRep (typeOf (undefined :: e)) "): " ++
     show m ++ "x" ++ show n ++ ">"
