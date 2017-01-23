{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ViewPatterns #-}
-- |
-- Module      : Graphics.Image.Interface.Vector.Unboxed
-- Copyright   : (c) Alexey Kuleshevich 2017
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Graphics.Image.Interface.Vector.Unboxed (
  U, VU(..), VU.Unbox, Image(..), fromUnboxedVector, toUnboxedVector, fromIx, toIx, checkDims
  ) where

import Prelude hiding (map, zipWith)
#if !MIN_VERSION_base(4,8,0)
import Data.Functor
#endif
import qualified Data.Vector.Unboxed as VU
import Graphics.Image.Interface as I
import Graphics.Image.Interface.Vector.Generic
import Graphics.Image.Interface.Vector.Unboxing()



-- | Unboxed 'Vector' representation.
data VU = VU

data U

type instance Repr (V U) = VU.Vector

instance Show U where
  show _ = "Unboxed"

instance Show VU where
  show _ = "VectorUnboxed"

instance SuperClass VU cs e => BaseArray VU cs e where
  type SuperClass VU cs e =
    (ColorSpace cs e, Num (Pixel cs e), VU.Unbox (Components cs e))

  data Image VU cs e = VUImage !(Image (V U) cs e)

  dims (VUImage img) = dims img
  {-# INLINE dims #-}



instance (MArray VU cs e, BaseArray VU cs e) => Array VU cs e where

  type Manifest VU = VU

  makeImage !sh = VUImage . makeImage sh
  {-# INLINE makeImage #-}

  makeImageWindowed !sh !window f g = VUImage $ makeImageWindowed sh window f g
  {-# INLINE makeImageWindowed #-}
  
  scalar = VUImage . scalar
  {-# INLINE scalar #-}

  index00 (VUImage img) = index00 img
  {-# INLINE index00 #-}
  
  map f (VUImage img) = VUImage $ I.map f img
  {-# INLINE map #-}

  imap f (VUImage img) = VUImage $ I.imap f img
  {-# INLINE imap #-}
  
  zipWith f (VUImage img1) (VUImage img2) = VUImage $ I.zipWith f img1 img2
  {-# INLINE zipWith #-}

  izipWith f (VUImage img1) (VUImage img2) = VUImage $ I.izipWith f img1 img2
  {-# INLINE izipWith #-}

  traverse (VUImage img) f g = VUImage $ I.traverse img f g
  {-# INLINE traverse #-}

  traverse2 (VUImage img1) (VUImage img2) f g = VUImage $ I.traverse2 img1 img2 f g
  {-# INLINE traverse2 #-}

  transpose (VUImage img) = VUImage $ I.transpose img
  {-# INLINE transpose #-}

  backpermute !sz f (VUImage img) = VUImage $ I.backpermute sz f img
  {-# INLINE backpermute #-}
  
  fromLists = VUImage . I.fromLists
  {-# INLINE fromLists #-}

  fold f !px0 (VUImage img) = fold f px0 img
  {-# INLINE fold #-}

  foldIx f !px0 (VUImage img) = foldIx f px0 img
  {-# INLINE foldIx #-}

  (|*|) (VUImage img1) (VUImage img2) = VUImage (img1 |*| img2)
  {-# INLINE (|*|) #-}

  eq (VUImage img1) (VUImage img2) = img1 == img2
  {-# INLINE eq #-}

  compute (VUImage img) = VUImage $! compute img
  {-# INLINE compute #-}

  toManifest = id
  {-# INLINE toManifest #-}


instance BaseArray VU cs e => MArray VU cs e where
  
  data MImage s VU cs e = MVUImage (MImage s (V U) cs e)
                              

  unsafeIndex (VUImage img) = unsafeIndex img
  {-# INLINE unsafeIndex #-}

  deepSeqImage (VUImage img) = deepSeqImage img
  {-# INLINE deepSeqImage #-}

  foldl f !px0 (VUImage img) = I.foldl f px0 img
  {-# INLINE foldl #-}

  foldr f !px0 (VUImage img) = I.foldr f px0 img
  {-# INLINE foldr #-}

  makeImageM !sh f = VUImage <$> makeImageM sh f
  {-# INLINE makeImageM #-}

  mapM f (VUImage img) = VUImage <$> I.mapM f img
  {-# INLINE mapM #-}

  mapM_ f (VUImage img) = I.mapM_ f img
  {-# INLINE mapM_ #-}

  foldM f !px0 (VUImage img) = I.foldM f px0 img
  {-# INLINE foldM #-}

  foldM_ f !px0 (VUImage img) = I.foldM_ f px0 img
  {-# INLINE foldM_ #-}

  mdims (MVUImage mimg) = mdims mimg
  {-# INLINE mdims #-}

  thaw (VUImage img) = MVUImage <$> I.thaw img
  {-# INLINE thaw #-}

  freeze (MVUImage img) = VUImage <$> I.freeze img
  {-# INLINE freeze #-}

  new !ix = MVUImage <$> I.new ix
  {-# INLINE new #-}

  read (MVUImage img) = I.read img
  {-# INLINE read #-}

  write (MVUImage img) = I.write img
  {-# INLINE write #-}

  swap (MVUImage img) = I.swap img
  {-# INLINE swap #-}



-- | Convert an image to a flattened Unboxed 'VU.Vector'. It is a __O(1)__ opeartion.
--
-- >>> toUnboxedVector $ makeImage (3, 2) (\(i, j) -> PixelY $ fromIntegral (i+j))
-- fromList [<Luma:(0.0)>,<Luma:(1.0)>,<Luma:(1.0)>,<Luma:(2.0)>,<Luma:(2.0)>,<Luma:(3.0)>]
--
toUnboxedVector :: Array VU cs e => Image VU cs e -> VU.Vector (Pixel cs e)
toUnboxedVector (VUImage img) = toVector img
{-# INLINE toUnboxedVector #-}


-- | Construct a two dimensional image with @m@ rows and @n@ columns from a flat
-- Unboxed 'VU.Vector' of length @k@. It is a __O(1)__ opeartion. Make sure that @m * n = k@.
--
-- >>> fromUnboxedVector (200, 300) $ generate 60000 (\i -> PixelY $ fromIntegral i / 60000)
-- <Image VectorUnboxed Luma: 200x300>
--
-- <<images/grad_fromVector.png>>
-- 
fromUnboxedVector :: Array VU cs e => (Int, Int) -> VU.Vector (Pixel cs e) -> Image VU cs e
fromUnboxedVector !sz !v = VUImage $ fromVector sz v
{-# INLINE fromUnboxedVector #-}
