{-# LANGUAGE GeneralizedNewtypeDeriving
           , RecordWildCards
           , OverloadedStrings 
           , TemplateHaskell #-}

module Graphics.Rendering.Canvas
  ( RenderM()
  , liftC
  , getStyleAttrib
  , runRenderM
  , accumStyle
  , newPath
  , moveTo
  , relLineTo
  , relCurveTo
  , closePath
  , stroke
  , fill
  , clip
  , transform
  , save
  , restore
  , strokeTexture
  , fillTexture
  , fromLineCap
  , fromLineJoin
  ) where

import           Control.Applicative      ((<$>))
import           Control.Arrow            ((***))
import           Control.Lens             (makeLenses, (.=), use)
import           Control.Monad.State
import qualified Control.Monad.StateStack as SS

import           Data.Default.Class       (Default(..))
import           Data.Maybe (fromMaybe)
import           Data.NumInstances        ()
import qualified Data.Text                as T
import           Data.Text                (Text)
import           Data.Word                (Word8)

import           Diagrams.Prelude         (Monoid(mempty))
import           Diagrams.Attributes      (Color(..),LineCap(..),LineJoin(..), 
                                          SomeColor(..), colorToSRGBA)
import           Diagrams.Core.Style      (Style, AttributeClass, getAttr)
import           Diagrams.Core.Types      (fromOutput)
import           Diagrams.TwoD.Attributes (Texture(..), getLineWidth, 
                                           LGradient, RGradient)
import           Diagrams.TwoD.Types      (R2(..))
import qualified Graphics.Blank           as BC
import qualified Graphics.Blank.Style     as S

data CanvasState = CanvasState { _accumStyle :: Style R2
                               , _csPos :: (Float, Float) }

makeLenses ''CanvasState

instance Default CanvasState where
  def = CanvasState { _accumStyle = mempty
                    , _csPos = (0,0) }

type RenderM a = SS.StateStackT CanvasState BC.Canvas a

liftC :: BC.Canvas a -> RenderM a
liftC = lift

runRenderM :: RenderM a -> BC.Canvas a
runRenderM = flip SS.evalStateStackT def

move :: (Float, Float) -> RenderM ()
move p = do csPos .= p

save :: RenderM ()
save = SS.save >> liftC (BC.save ())

restore :: RenderM ()
restore = liftC (BC.restore ()) >> SS.restore

newPath :: RenderM ()
newPath = liftC $ BC.beginPath ()

closePath :: RenderM ()
closePath = liftC $ BC.closePath ()

moveTo :: Double -> Double -> RenderM ()
moveTo x y = do
  let x' = realToFrac x
      y' = realToFrac y
  liftC $ BC.moveTo (x', y')
  move (x', y')

relLineTo :: Double -> Double -> RenderM ()
relLineTo x y = do
  p <- use csPos
  let p' = p + (realToFrac x, realToFrac y)
  liftC $ BC.lineTo p'
  move p'

relCurveTo :: Double -> Double -> Double -> Double -> Double -> Double -> RenderM ()
relCurveTo ax ay bx by cx cy = do
  p <- use csPos
  let [(ax',ay'),(bx',by'),(cx',cy')] = map ((p +) . (realToFrac *** realToFrac))
                                          [(ax,ay),(bx,by),(cx,cy)]
  liftC $ BC.bezierCurveTo (ax',ay',bx',by',cx',cy')
  move (cx', cy')

-- | Get an accumulated style attribute from the render monad state.
getStyleAttrib :: AttributeClass a => (a -> b) -> RenderM (Maybe b)
getStyleAttrib f = (fmap f . getAttr) <$> use accumStyle

stroke :: RenderM ()
stroke = do

  -- From the HTML5 canvas specification regarding line width:
  --
  --   "On setting, zero, negative, infinite, and NaN values must be
  --   ignored, leaving the value unchanged; other values must change
  --   the current value to the new value.
  --
  -- Hence we must implement a line width of zero by simply not
  -- sending a stroke command.

  -- default value of 1 is arbitary, anything > 0 will do.
  w <- fromMaybe 1 <$> getStyleAttrib (fromOutput . getLineWidth)
  when (w > 0) (liftC $ BC.stroke ())

fill :: RenderM ()
fill = liftC $ BC.fill ()

clip :: RenderM ()
clip = liftC $ BC.clip ()

byteRange :: Double -> Word8
byteRange d = floor (d * 255)

showColorJS :: (Color c) => c -> Text
showColorJS c = T.concat
    [ "rgba("
        , s r, ","
    , s g, ","
    , s b, ","
    , T.pack (show a)
    , ")"
    ]
  where s :: Double -> Text
        s = T.pack . show . byteRange
        (r,g,b,a) = colorToSRGBA c

transform :: Double -> Double -> Double -> Double -> Double -> Double -> RenderM ()
transform ax ay bx by tx ty = liftC $ BC.transform vs
    where 
      vs = (realToFrac ax,realToFrac ay
           ,realToFrac bx,realToFrac by
           ,realToFrac tx,realToFrac ty)

withTexture :: Texture -> (Text -> BC.Canvas ()) 
                       -> (BC.CanvasGradient -> BC.Canvas ()) 
                       -> RenderM ()
withTexture (SC (SomeColor c)) f _ = liftC . f . showColorJS $ c
withTexture (LG grd) _ g           = liftC . g . lGradient $ grd
withTexture (RG grd) _ g           = liftC . g . rGradient $ grd

lGradient :: LGradient -> BC.CanvasGradient
lGradient = undefined

rGradient :: RGradient -> BC.CanvasGradient
rGradient = undefined

strokeTexture :: Texture -> RenderM ()
strokeTexture t@(SC _) = withTexture t S.strokeStyle mempty
strokeTexture t@(LG _) = withTexture t mempty S.strokeStyle
strokeTexture t@(RG _) = withTexture t mempty S.strokeStyle

fillTexture :: Texture  -> RenderM ()
fillTexture t@(SC _) = withTexture t S.fillStyle mempty
fillTexture t@(LG _) = withTexture t mempty S.fillStyle
fillTexture t@(RG _) = withTexture t mempty S.fillStyle

fromLineCap :: LineCap -> Text
fromLineCap LineCapRound  = "round"
fromLineCap LineCapSquare = "square"
fromLineCap _             = "butt"

fromLineJoin :: LineJoin -> Text
fromLineJoin LineJoinRound = "round"
fromLineJoin LineJoinBevel = "bevel"
fromLineJoin _             = "miter"

