{-# LANGUAGE TypeFamilies
           , MultiParamTypeClasses
           , FlexibleInstances
           , FlexibleContexts
           , GADTs
           , TypeSynonymInstances
           , DeriveDataTypeable
           , ViewPatterns
           , InstanceSigs
           , ScopedTypeVariables
  #-}
{-|
  The Canvas backend.
-}
module Diagrams.Backend.Canvas

  ( Canvas(..) -- rendering token

  , Options(..) -- for rendering options specific to Canvas
  ) where

import           Data.Tree
import           Control.Monad (when)
import qualified Data.Foldable as F
import           Data.Maybe (catMaybes, isJust, fromJust, fromMaybe)
import           Data.Typeable
import           Control.Lens                 hiding (transform, ( # ))
import           Control.Monad.State
import           Data.Typeable
import           GHC.Generics                 (Generic)

import           Diagrams.Prelude
import           Diagrams.TwoD.Adjust (adjustDia2D)
import           Diagrams.TwoD.Attributes     (splitTextureFills)
import           Diagrams.TwoD.Types          (R2(..))
import qualified Graphics.Blank as BC
import qualified Graphics.Rendering.Canvas as C
import           Graphics.Rendering.Canvas    (liftC, getStyleAttrib, accumStyle)
import           Diagrams.Core.Compile
import           Diagrams.Core.Types          (Annotation (..))
import           Diagrams.TwoD.Size           (sizePair)
import           Diagrams.TwoD.Text


-- | This data declaration is simply used as a token to distinguish this rendering engine.
data Canvas = Canvas
    deriving Typeable

instance Monoid (Render Canvas R2) where
  mempty  = C $ return ()
  (C c1) `mappend` (C c2) = C (c1 >> c2)

instance Backend Canvas R2 where
  data Render  Canvas R2 = C (C.RenderM ())
  type Result  Canvas R2 = BC.Canvas ()
  data Options Canvas R2 = CanvasOptions
          { _canvasSize   :: SizeSpec2D   -- ^ the requested size
          }

  renderRTree :: Canvas -> Options Canvas R2 -> RTree Canvas R2 Annotation -> Result Canvas R2
  renderRTree _ opts rt = evalState canvasOutput initialCanvasRenderState
    where
      canvasOutput :: State CanvasRenderState (BC.Canvas ())
      canvasOutput = do
        let C r = toRender rt
            (w,h) = sizePair (opts^.size)
                    -- This is where you can mess with the size
        return $ C.runRenderM $ r
  adjustDia c opts d = adjustDia2D size c opts (d # reflectY)

runC :: Render Canvas R2 -> C.RenderM ()
runC (C r) = r

toRender :: RTree Canvas R2 Annotation -> Render Canvas R2
toRender = fromRTree
  . Node (RStyle (mempty # recommendFillColor (transparent :: AlphaColour Double)))
  . (:[])
  . splitTextureFills
    where
      fromRTree (Node (RPrim p) _) = render Canvas p
      fromRTree (Node (RStyle sty) rs) = C $ do
        C.save
        canvasStyle sty
        accumStyle %= (<> sty)
        runC $ F.foldMap fromRTree rs
        C.stroke
        C.restore
      fromRTree (Node _ rs) = F.foldMap fromRTree rs

data CanvasRenderState = CanvasRenderState

initialCanvasRenderState :: CanvasRenderState
initialCanvasRenderState = CanvasRenderState

getSize :: Options Canvas R2 -> SizeSpec2D
getSize (CanvasOptions {_canvasSize = s}) = s

setSize :: Options Canvas R2 -> SizeSpec2D -> Options Canvas R2
setSize o s = o {_canvasSize = s}

size :: Lens' (Options Canvas R2) SizeSpec2D
size = lens getSize setSize

renderC :: (Renderable a Canvas, V a ~ R2) => a -> C.RenderM ()
renderC a = case (render Canvas a) of C r -> r

canvasStyle :: Style v -> C.RenderM ()
canvasStyle s = sequence_
              . catMaybes $ [ handle lWidth
                            , handle lJoin
                            , handle lCap
                            , handle opacity_
                            ]
  where handle :: (AttributeClass a) => (a -> C.RenderM ()) -> Maybe (C.RenderM ())
        handle f = f `fmap` getAttr s
        lWidth = liftC . BC.lineWidth . realToFrac . fromOutput . getLineWidth
        lCap = liftC . BC.lineCap . C.fromLineCap . getLineCap
        lJoin = liftC .  BC.lineJoin . C.fromLineJoin . getLineJoin
        opacity_ = liftC . BC.globalAlpha . realToFrac . getOpacity

canvasTransf :: Transformation R2 -> C.RenderM ()
canvasTransf t = C.transform a1 a2 b1 b2 c1 c2
  where (unr2 -> (a1,a2)) = apply t unitX
        (unr2 -> (b1,b2)) = apply t unitY
        (unr2 -> (c1,c2)) = transl t

instance Renderable (Segment Closed R2) Canvas where
  render _ (Linear (OffsetClosed (R2 x y))) = C $ C.relLineTo x y
  render _ (Cubic (R2 x1 y1)
                  (R2 x2 y2)
                  (OffsetClosed (R2 x3 y3)))
    = C $ C.relCurveTo x1 y1 x2 y2 x3 y3

instance Renderable (Trail R2) Canvas where
  render _ = withTrail renderLine renderLoop
    where
      renderLine ln = C $ do
        mapM_ renderC (lineSegments ln)
      renderLoop lp = C $ do
        case loopSegments lp of
          (segs, Linear _) -> mapM_ renderC segs
          _ -> mapM_ renderC (lineSegments . cutLoop $ lp)
        C.closePath

instance Renderable (Path R2) Canvas where
  render _ p = C $ do
    canvasPath p
    f <- getStyleAttrib getFillTexture
    s <- getStyleAttrib getLineTexture
    when (isJust f) (C.fillColor (fromJust f) >> C.fill)
    C.strokeColor (fromMaybe (SC (SomeColor black)) s)
    C.stroke

-- Add a path to the Canvas context, without stroking or filling it.
canvasPath :: Path R2 -> C.RenderM ()
canvasPath (Path trs) = do
    C.newPath
    F.mapM_ renderTrail trs
  where
    renderTrail (viewLoc -> (unp2 -> p, tr)) = do
      uncurry C.moveTo p
      renderC tr
