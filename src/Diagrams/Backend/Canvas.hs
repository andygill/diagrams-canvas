{-# LANGUAGE TypeFamilies
           , MultiParamTypeClasses
           , FlexibleInstances
           , FlexibleContexts
           , TypeSynonymInstances
           , DeriveDataTypeable
           , ViewPatterns
  #-}
{-|
  The Canvas backend.
-}
module Diagrams.Backend.Canvas

  ( Canvas(..) -- rendering token

  , Options(..) -- for rendering options specific to Canvas
  ) where

import           Control.Monad (when)
import qualified Data.Foldable as F
import           Data.Maybe (catMaybes)
import           Data.Typeable
import           Control.Lens                 hiding (transform, ( # ))
import           Control.Monad.State
import           Data.Typeable
import           GHC.Generics                 (Generic)

import           Diagrams.Prelude
import           Diagrams.TwoD.Adjust (adjustDia2D)
import qualified Graphics.Blank as BC
import qualified Graphics.Rendering.Canvas as C
import           Diagrams.Core.Compile
import           Diagrams.Core.Types          (Annotation (..))
import           Diagrams.TwoD.Size           (sizePair)


-- | This data declaration is simply used as a token to distinguish this rendering engine.
data Canvas = Canvas
    deriving Typeable

instance Monoid (Render Canvas R2) where
  mempty  = C $ return ()
  (C c1) `mappend` (C c2) = C (c1 >> c2)

instance Backend Canvas R2 where
  data Render  Canvas R2 = C (C.Render ())
  type Result  Canvas R2 = BC.Canvas ()
  data Options Canvas R2 = CanvasOptions
          { _canvasSize   :: SizeSpec2D   -- ^ the requested size
          }

  renderRTree _ opts rt = evalState canvasOutput initialCanvasRenderState
    where
      canvasOutput = do
        let C r = toRender rt
            (w,h) = sizePair (opts^.size)
        return $ undefined -- R.svgHeader w h (opts^.svgDefinitions) $ cvs

{-
  withStyle _ s t (C r) = C $ do
    C.withStyle (canvasTransf t) (canvasStyle s) r

  doRender _ (CanvasOptions _) (C r) = C.doRender r

-}
--  adjustDia c opts d = adjustDia2D size c opts (d # reflectY)
  adjustDia c opts d = adjustDia2D size c opts
                       (d # reflectY # fcA transparent) --  # lw 0.01)


toRender :: RTree Canvas R2 Annotation -> Render Canvas R2
toRender = undefined

data CanvasRenderState = CanvasRenderState

initialCanvasRenderState :: CanvasRenderState
initialCanvasRenderState = CanvasRenderState

getSize :: Options Canvas R2 -> SizeSpec2D
getSize (CanvasOptions {_canvasSize = s}) = s

setSize :: Options Canvas R2 -> SizeSpec2D -> Options Canvas R2
setSize o s = o {_canvasSize = s}

size :: Lens' (Options Canvas R2) SizeSpec2D
size = lens getSize setSize

renderC :: (Renderable a Canvas, V a ~ R2) => a -> C.Render ()
renderC a = case (render Canvas a) of C r -> r

canvasStyle :: Style v -> C.Render ()
canvasStyle = undefined
{-
canvasStyle s = foldr (>>) (return ())
              . catMaybes $ [ {-handle fColor
                            , handle lColor
                            , -}handle lWidth
                            , handle lJoin
                            , handle lCap
                            , handle opacity_
                            ]
  where handle :: (AttributeClass a) => (a -> C.Render ()) -> Maybe (C.Render ())
        handle f = f `fmap` getAttr s
--        lColor = C.strokeColor . getLineColor 
--        fColor = C.fillColor . getFillColor 
        lWidth = C.lineWidth . getLineWidth
        lCap = C.lineCap . getLineCap
        lJoin = C.lineJoin . getLineJoin
        opacity_ = C.globalAlpha . getOpacity
-}

canvasTransf :: Transformation R2 -> C.Render ()
canvasTransf t = C.transform a1 a2 b1 b2 c1 c2
  where (unr2 -> (a1,a2)) = apply t unitX
        (unr2 -> (b1,b2)) = apply t unitY
        (unr2 -> (c1,c2)) = transl t

{-
instance Renderable (Segment R2) Canvas where
  render _ (Linear v) = C $ uncurry C.relLineTo (unr2 v)
  render _ (Cubic (unr2 -> (x1,y1))
                  (unr2 -> (x2,y2))
                  (unr2 -> (x3,y3)))
    = C $ C.relCurveTo x1 y1 x2 y2 x3 y3
-}

{-
instance Renderable (Trail R2) Canvas where
  render _ (Trail segs c) = C $ do
    mapM_ renderC segs
    when c $ C.closePath
-}

{-
INSTANCE Renderable (Path R2) Canvas where
  render _ (Path trs) = C $ C.newPath >> F.mapM_ renderTrail trs
    where renderTrail (unp2 -> p, tr) = do
            uncurry C.moveTo p
            renderC tr
-}