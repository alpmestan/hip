{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ViewPatterns #-}
-- |
-- Module      : Graphics.Image.Interface.Repa.Generic
-- Copyright   : (c) Alexey Kuleshevich 2017
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Graphics.Image.Interface.Repa.Generic where

import Prelude as P
import Data.Typeable (Typeable)
import Data.Array.Repa.Index
import qualified Data.Array.Repa as R
import qualified Data.Array.Repa.Eval as R

import Graphics.Image.ColorSpace.Binary (Bit(..))
import Graphics.Image.Interface as I
import qualified Graphics.Image.Interface.Vector.Unboxed as IVU
import qualified Graphics.Image.Interface.Vector.Generic as IVG
import Graphics.Image.Interface.Repa.Helpers


type family Repr arr :: *


-- | Repa Array representation, which is computed in parallel.
data RP r = RP r

-- | Repa Array representation, which is computed sequentially. 
data RS r = RS r

instance Show r => Show (RP r) where
  show (RP r) = "RepaParallel " ++ show r
  
instance Show r => Show (RS r) where
  show (RS r) = "RepaSequential " ++ show r


-----------------------
-- Sequential Arrays --
-----------------------

instance Elt (RS r) cs e => BaseArray (RS r) cs e where
  type Elt (RS r) cs e = (Show r, ColorSpace cs, Num e, Typeable e,
                          R.Target (Repr (RS r)) (Pixel cs e),
                          R.Source (Repr (RS r)) (Pixel cs e),
                          BaseArray (IVG.V r) cs e,
                          R.Elt e, R.Elt (Pixel cs e))
  
  data Image (RS r) cs e = SScalar !(Pixel cs e)
                         | STImage !(R.Array (Repr (RS r)) R.DIM2 (Pixel cs e))
                         | SDImage !(R.Array R.D R.DIM2 (Pixel cs e))
                       
  dims (SScalar _                          ) = (1, 1)
  dims (STImage (R.extent -> (Z :. m :. n))) = (m, n)
  dims (SDImage (R.extent -> (Z :. m :. n))) = (m, n)
  {-# INLINE dims #-}


instance (BaseArray (RS r) cs e) => Array (RS r) cs e where

  type Manifest (RS r) = Manifest (IVG.V r)
  
  makeImage !(checkDims "RS.makeImage" -> (m, n)) f =
    SDImage $ R.fromFunction (Z :. m :. n) (f . sh2ix)
  {-# INLINE makeImage #-}
  
  makeImageWindowed !(checkDims "RS.makeImage" -> (m, n)) !window getWindowPx getBorderPx  =
    SDImage $ R.delay $ makeWindowed (Z :. m :. n) window
    (R.fromFunction (Z :. m :. n) (getWindowPx . sh2ix))
     (R.fromFunction (Z :. m :. n) (getBorderPx . sh2ix))
    
  singleton = SScalar
  {-# INLINE singleton #-}

  index00 (SScalar px)  = px
  index00 (STImage arr) = R.index arr (Z :. 0 :. 0)
  index00 (SDImage arr) = R.index arr (Z :. 0 :. 0)
  {-# INLINE index00 #-}

  map f (SScalar px)  = SScalar (f px)
  map f (STImage arr) = SDImage (R.map f arr)
  map f (SDImage arr) = SDImage (R.map f arr)
  {-# INLINE map #-}

  imap f (SScalar px)  = SScalar (f (0, 0) px)
  imap f (STImage arr) = SDImage (imapR f arr)
  imap f (SDImage arr) = SDImage (imapR f arr)
  {-# INLINE imap #-}

  zipWith f (SScalar px1) (SScalar px2) = SScalar (f px1 px2)
  zipWith f (SScalar px1) !img2         = I.map (f px1) img2
  zipWith f !img1         (SScalar px2) = I.map (`f` px2) img1
  zipWith f !img1         !img2         =
    SDImage (R.zipWith f (getDelayedS img1) (getDelayedS img2))
  {-# INLINE zipWith #-}

  izipWith f (SScalar px1) (SScalar px2) = SScalar (f (0, 0) px1 px2)
  izipWith f (SScalar px1) !img2         = imap (`f` px1) img2
  izipWith f !img1         (SScalar px2) = imap (\ !ix !px -> f ix px px2) img1
  izipWith f !img1         !img2         =
    SDImage (izipWithR f (getDelayedS img1) (getDelayedS img2))
  {-# INLINE izipWith #-}
  
  traverse !img getNewDims getNewPx =
    SDImage (traverseR (getDelayedS img) getNewDims getNewPx)
  {-# INLINE traverse #-}

  traverse2 !img1 !img2 getNewDims getNewPx =
    SDImage (traverse2R (getDelayedS img1) (getDelayedS img2) getNewDims getNewPx)
  {-# INLINE traverse2 #-}

  transpose (SDImage arr) = SDImage (R.transpose arr)
  transpose (STImage arr) = SDImage (R.transpose arr)
  transpose !img          = img
  {-# INLINE transpose #-}

  backpermute !newDims g !img = SDImage (backpermuteR (getDelayedS img) newDims g)
  {-# INLINE backpermute #-}

  fromLists = STImage . fromListsR
  {-# INLINE fromLists #-}

  fold f !px0 (SDImage arr) = R.foldAllS f px0 arr
  fold f !px0 (STImage arr) = R.foldAllS f px0 arr
  fold f !px0 (SScalar px)  = f px px0
  {-# INLINE fold #-}

  foldIx f !px0 (SDImage arr) = foldIxS f px0 arr
  foldIx f !px0 (STImage arr) = foldIxS f px0 arr
  foldIx f !px0 (SScalar px)  = f px0 (0, 0) px
  {-# INLINE foldIx #-}

  eq (SScalar px1) (SScalar px2) = px1 == px2
  eq !img1 !img2 = R.equalsS (getDelayedS img1) (getDelayedS img2)
  {-# INLINE eq #-}

  compute !img@(SScalar _) = img
  compute !img@(STImage _) = img
  compute (SDImage arr)    = STImage (R.computeS arr)
  {-# INLINE compute #-}

  (|*|) img1@(STImage arr1) img2@(STImage arr2) =
     SDImage (multR (show img1 ++ " X " ++ show img2) arr1 arr2)
  (|*|) img1@(SDImage _) !img2            = compute img1 |*| img2
  (|*|) !img1            img2@(SDImage _) = img1 |*| compute img2
  (|*|) (SScalar px1)    !img2            = STImage (singletonR px1) |*| img2
  (|*|) !img1            (SScalar px2)    = img1 |*| STImage (singletonR px2)
  {-# INLINE (|*|) #-}

  toManifest _ = error $ "RS.toManifest: Cannot convert generic Repa " ++
                         "representation to a generic Vector."
  {-# INLINE toManifest #-}


---------------------
-- Parallel Arrays --
---------------------



instance Elt (RP r) cs e => BaseArray (RP r) cs e where
  type Elt (RP r) cs e = (Show r, ColorSpace cs, Num e, Typeable e,
                          R.Target (Repr (RP r)) (Pixel cs e),
                          R.Source (Repr (RP r)) (Pixel cs e),
                          BaseArray (IVG.V r) cs e,
                          Repr (RP r) ~ Repr (RS r),
                          R.Elt e, R.Elt (Pixel cs e))
  
  data Image (RP r) cs e = PScalar !(Pixel cs e)
                         | PTImage !(R.Array (Repr (RP r)) R.DIM2 (Pixel cs e))
                         | PDImage !(R.Array R.D R.DIM2 (Pixel cs e))
                       
  dims (PScalar _                          ) = (1, 1)
  dims (PTImage (R.extent -> (Z :. m :. n))) = (m, n)
  dims (PDImage (R.extent -> (Z :. m :. n))) = (m, n)
  {-# INLINE dims #-}


instance (BaseArray (RP r) cs e) => Array (RP r) cs e where

  type Manifest (RP r) = Manifest (IVG.V r)
  
  makeImage !(checkDims "RP.makeImage" -> (m, n)) f =
    PDImage $ R.fromFunction (Z :. m :. n) (f . sh2ix)
  {-# INLINE makeImage #-}
  
  makeImageWindowed !(checkDims "RP.makeImage" -> (m, n)) !window getWindowPx getBorderPx  =
    PDImage $ R.delay $ makeWindowed (Z :. m :. n) window
    (R.fromFunction (Z :. m :. n) (getWindowPx . sh2ix))
     (R.fromFunction (Z :. m :. n) (getBorderPx . sh2ix))
    
  singleton = PScalar
  {-# INLINE singleton #-}

  index00 (PScalar px)  = px
  index00 (PTImage arr) = R.index arr (Z :. 0 :. 0)
  index00 (PDImage arr) = R.index arr (Z :. 0 :. 0)
  {-# INLINE index00 #-}

  map f (PScalar px)  = PScalar (f px)
  map f (PTImage arr) = PDImage (R.map f arr)
  map f (PDImage arr) = PDImage (R.map f arr)
  {-# INLINE map #-}

  imap f (PScalar px)  = PScalar (f (0, 0) px)
  imap f (PTImage arr) = PDImage (imapR f arr)
  imap f (PDImage arr) = PDImage (imapR f arr)
  {-# INLINE imap #-}

  zipWith f (PScalar px1) (PScalar px2) = PScalar (f px1 px2)
  zipWith f (PScalar px1) !img2         = I.map (f px1) img2
  zipWith f !img1         (PScalar px2) = I.map (`f` px2) img1
  zipWith f !img1         !img2         =
    PDImage (R.zipWith f (getDelayedP img1) (getDelayedP img2))
  {-# INLINE zipWith #-}

  izipWith f (PScalar px1) (PScalar px2) = PScalar (f (0, 0) px1 px2)
  izipWith f (PScalar px1) !img2         = imap (`f` px1) img2
  izipWith f !img1         (PScalar px2) = imap (\ !ix !px -> f ix px px2) img1
  izipWith f !img1         !img2         =
    PDImage (izipWithR f (getDelayedP img1) (getDelayedP img2))
  {-# INLINE izipWith #-}
  
  traverse !img getNewDims getNewPx =
    PDImage (traverseR (getDelayedP img) getNewDims getNewPx)
  {-# INLINE traverse #-}

  traverse2 !img1 !img2 getNewDims getNewPx =
    PDImage (traverse2R (getDelayedP img1) (getDelayedP img2) getNewDims getNewPx)
  {-# INLINE traverse2 #-}

  transpose (PDImage arr) = PDImage (R.transpose arr)
  transpose (PTImage arr) = PDImage (R.transpose arr)
  transpose !img          = img
  {-# INLINE transpose #-}

  backpermute !newDims g !img = PDImage (backpermuteR (getDelayedP img) newDims g)
  {-# INLINE backpermute #-}

  fromLists = PTImage . fromListsR
  {-# INLINE fromLists #-}

  -- Repa only supports parallel folding for Unboxed Arrays, have to fallback to
  -- sequential processing for fold and foldIx
  fold !f !px0 !img = fold f px0 (toRS img)
  {-# INLINE fold #-}

  foldIx !f !px0 !img = foldIx f px0 (toRS img)
  {-# INLINE foldIx #-}


  eq (PScalar px1) (PScalar px2) = px1 == px2
  eq !img1 !img2 =
    case R.equalsP (getDelayedP img1) (getDelayedP img2) of
      Just e  -> e
      Nothing -> error $ "RP.eq: impossible happened."
  {-# INLINE eq #-}

  compute !img@(PScalar _) = img
  compute !img@(PTImage _) = img
  compute (PDImage arr)    = arrManifest `R.deepSeqArray` PTImage arrManifest
     where arrManifest = R.suspendedComputeP arr
  {-# INLINE compute #-}

  (|*|) img1@(PTImage arr1) img2@(PTImage arr2) =
     PDImage (multR (show img1 ++ " X " ++ show img2) arr1 arr2)
  (|*|) img1@(PDImage _) !img2            = compute img1 |*| img2
  (|*|) !img1            img2@(PDImage _) = img1 |*| compute img2
  (|*|) (PScalar px1)    !img2            = PTImage (singletonR px1) |*| img2
  (|*|) !img1            (PScalar px2)    = img1 |*| PTImage (singletonR px2)
  {-# INLINE (|*|) #-}

  toManifest _ = error $ "RP.toManifest: Cannot convert generic Repa " ++
                         "representation to a generic Vector."
  {-# INLINE toManifest #-}



----------------------
-- Helper functions --
----------------------

sh2ix :: DIM2 -> (Int, Int)
sh2ix (Z :. i :. j) = (i, j)
{-# INLINE sh2ix #-}

ix2sh :: (Int, Int) -> DIM2
ix2sh !(i, j) = Z :. i :. j 
{-# INLINE ix2sh #-}


toRS :: Repr (RP r) ~ Repr (RS r) => Image (RP r) cs e -> Image (RS r) cs e
toRS (PScalar px)  = SScalar px
toRS (PDImage img) = SDImage img
toRS (PTImage img) = STImage img

toRP :: Repr (RP r) ~ Repr (RS r) => Image (RS r) cs e -> Image (RP r) cs e
toRP (SScalar px)  = PScalar px
toRP (SDImage img) = PDImage img
toRP (STImage img) = PTImage img


imapR
  :: R.Source r2 b =>
     ((Int, Int) -> b -> c) -> R.Array r2 DIM2 b -> R.Array R.D DIM2 c
imapR f !arr = R.zipWith f (R.fromFunction (R.extent arr) sh2ix) arr


-- | Combine two arrays, element-wise, with index aware operator. If the extent of
-- the two array arguments differ, then the resulting array's extent is their
-- intersection.
izipWithR
  :: (R.Source r2 t1, R.Source r1 t)
  => ((Int, Int) -> t -> t1 -> c)
  -> R.Array r1 DIM2 t
  -> R.Array r2 DIM2 t1
  -> R.Array R.D DIM2 c
izipWithR f !arr1 !arr2 =
  (R.traverse2 arr1 arr2 getNewDims getNewPx) where
    getNewPx !getPx1 !getPx2 !sh = f (sh2ix sh) (getPx1 sh) (getPx2 sh)
    getNewDims (Z :. m1 :. n1) (Z :. m2 :. n2) = Z :. min m1 m2 :. min n1 n2
    {-# INLINE getNewPx #-}
{-# INLINE izipWithR #-}


traverseR
  :: R.Source r c
  => R.Array r DIM2 c
  -> ((Int, Int) -> (Int, Int))
  -> (((Int, Int) -> c) -> (Int, Int) -> b)
  -> R.Array R.D DIM2 b
traverseR !arr getNewDims getNewPx =
  R.traverse arr (ix2sh . checkDims "traverseR" . getNewDims . sh2ix) getNewE
  where
    getNewE getPx = getNewPx (getPx . ix2sh) . sh2ix
    {-# INLINE getNewE #-}
{-# INLINE traverseR #-}

traverse2R
  :: (R.Source r2 c1, R.Source r1 c)
  => R.Array r1 DIM2 c
  -> R.Array r2 DIM2 c1
  -> ((Int, Int) -> (Int, Int) -> (Int, Int))
  -> (((Int, Int) -> c) -> ((Int, Int) -> c1) -> (Int, Int) -> c2)
  -> R.Array R.D DIM2 c2
traverse2R !arr1 !arr2 getNewDims getNewPx =
  R.traverse2 arr1 arr2 getNewSh getNewE
  where getNewE getPx1 getPx2 = getNewPx (getPx1 . ix2sh) (getPx2 . ix2sh) . sh2ix
        {-# INLINE getNewE #-}
        getNewSh !sh1 !sh2 =
          ix2sh . checkDims "traverse2R" $ getNewDims (sh2ix sh1) (sh2ix sh2)
        {-# INLINE getNewSh #-}
{-# INLINE traverse2R #-}

backpermuteR
  :: R.Source r e
  => R.Array r DIM2 e
  -> (Int, Int)
  -> ((Int, Int) -> (Int, Int))
  -> R.Array R.D DIM2 e
backpermuteR !arr newDims g =
  R.backpermute
    (ix2sh (checkDims "backpermuteR" newDims))
    (ix2sh . g . sh2ix)
    arr
{-# INLINE backpermuteR #-}


fromListsR :: (R.Target r e) => [[e]] -> R.Array r DIM2 e
fromListsR ls =
  if all (== n) (P.map length ls)
    then R.fromList (Z :. m :. n) . concat $ ls
    else error "fromListsR: Inner lists do not all have an equal length."
  where
    !(m, n) = checkDims "fromListsR" (length ls, length $ head ls)
{-# INLINE fromListsR #-}



multR
  :: (Num a, R.Elt a, R.Target r a, R.Source r a)
  => String -> R.Array r DIM2 a -> R.Array r DIM2 a -> R.Array R.D DIM2 a
multR errMsg !arr1 !arr2 =
  if n1 /= m2
    then error $
         "Inner dimensions of multiplied images must be the same, but received: " ++ errMsg
    else R.fromFunction (Z :. m1 :. n2) $ getPx
  where
    (Z :. m1 :. n1) = R.extent arr1
    (Z :. m2 :. n2) = R.extent arr2
    getPx (Z :. i :. j) =
      R.sumAllS
        (R.slice arr1 (R.Any :. (i :: Int) :. R.All) R.*^
         R.slice arr2 (R.Any :. (j :: Int)))
    {-# INLINE getPx #-}
{-# INLINE multR #-}


singletonR :: R.Target r a => a -> R.Array r DIM2 a
singletonR !px = R.computeS $ R.fromFunction (Z :. 1 :. 1) $ const px


getDelayedS :: Array (RS r) cs e => Image (RS r) cs e -> R.Array R.D DIM2 (Pixel cs e)
getDelayedS (STImage arr) = R.delay arr
getDelayedS (SDImage arr) = arr
getDelayedS (SScalar px)  = R.fromFunction (Z :. 1 :. 1) (const px)
{-# INLINE getDelayedS #-}

getDelayedP :: Array (RP r) cs e => Image (RP r) cs e -> R.Array R.D DIM2 (Pixel cs e)
getDelayedP (PTImage arr) = R.delay arr
getDelayedP (PDImage arr) = arr
getDelayedP (PScalar px)  = R.fromFunction (Z :. 1 :. 1) (const px)
{-# INLINE getDelayedP #-}



-- -- | Retrieve an underlying Repa array from an image.
-- toRepaArray
--   :: (Array arr cs e, Array RS cs e, Exchangable arr RS)
--   => Image arr cs e -> R.Array R.U DIM2 (Pixel cs e)
-- toRepaArray img =
--   case compute (exchange RS img) of
--     STImage arr -> arr
--     SDImage arr -> R.computeS arr -- shouldn't occur, but for completeness
--     SScalar px -> R.computeS $ R.fromFunction (Z :. 1 :. 1) $ const px

instance R.Elt Bit where
  touch (Bit w) = R.touch w
  {-# INLINE touch #-}
  
  zero     = 0
  {-# INLINE zero #-}
  
  one      = 1
  {-# INLINE one #-}


instance (ColorSpace cs, R.Elt e, Num e) => R.Elt (Pixel cs e) where
  touch !px = P.mapM_ (R.touch . getPxCh px) (enumFrom (toEnum 0)) 
  {-# INLINE touch #-}
  
  zero     = 0
  {-# INLINE zero #-}
  
  one      = 1
  {-# INLINE one #-}


addIxArr
  :: R.Source r2 b =>
     R.Array r2 DIM2 b -> R.Array R.D DIM2 ((Int, Int), b)
addIxArr !arr = R.zipWith (,) arrIx arr
  where
    !arrIx = R.fromFunction (R.extent arr) sh2ix
{-# INLINE addIxArr #-}


foldIxS
  :: R.Source r2 b =>
     (b -> (Int, Int) -> b -> b) -> b -> R.Array r2 DIM2 b -> b
foldIxS f !acc !arr = snd $ R.foldAllS g ((-1, 0), acc) arr'
  where
    !arr' = addIxArr arr
    g (accIx@(-1, _), acc') !(ix, px) = (accIx, f acc' ix px)
    g !(ix, px) (accIx@(-1, _), acc') = (accIx, f acc' ix px)
    g (acc1Ix, _) (acc2Ix, _) =
      error $ "foldIxS: Impossible happened. Received: " ++ show acc1Ix ++ " " ++ show acc2Ix
    {-# INLINE g #-}
{-# INLINE foldIxS #-}


foldIxPUnboxed
  :: (R.Source r2 b, IVU.Unbox b, Monad m)
  => (b -> (Int, Int) -> b -> b) -> b -> R.Array r2 DIM2 b -> m b
foldIxPUnboxed f !acc !arr = snd <$> R.foldAllP g ((-1, 0), acc) arr'
  where
    !arr' = addIxArr arr
    g (accIx@(-1, _), acc') !(ix, px) = (accIx, f acc' ix px)
    g !(ix, px) (accIx@(-1, _), acc') = (accIx, f acc' ix px)
    g (acc1Ix, _) (acc2Ix, _) =
      error $ "foldIxPUnboxed: Impossible happened. Received: " ++ show acc1Ix ++ " " ++ show acc2Ix
    {-# INLINE g #-}
{-# INLINE foldIxPUnboxed #-}

