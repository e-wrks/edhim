
-- | This module models an Edh world doing chat hosting business

module ChatWorld where

import           Prelude
-- import           Debug.Trace

import           GHC.Conc                       ( unsafeIOToSTM )

import           Control.Monad
import           Control.Monad.Reader
import           Control.Concurrent
import           Control.Concurrent.STM

import           Data.Text                      ( Text )
import qualified Data.Text                     as T

import qualified Data.HashMap.Strict           as Map

import           Language.Edh.EHI


-- * In this simple case, the input/output items between humans in the
-- real world and articles in the chat world are just textual messages

-- A sufficiently sophisticated Haskell + Edh application will include
-- more data structures to establish more interesting mechanics

type InputFromHuman = Text
type OutputToHuman = Text


-- * There must be some joint points for the chat world to be connected
-- to the real world, in this simple case, a singleton gate and many 
-- user-agents are defined as to be

-- Sophisticated applications will have far or near more complex
-- mechanics and laws of physics

-- | Joint physics of the only gate in a chat world 
data ChatAccessPoint = ChatAccessPoint {
    dismissAll :: IO () -- ^ the action to kick all chatters out
               -> IO () -- ^ the action installer
    , accomodateAgent :: (ChatUserAgent -> IO ()) -- ^ the entry
                      -> IO () -- ^ the entry installer
  }

-- | Joint physics of a user agent in a chat world
data ChatUserAgent = ChatUserAgent {
    cutoffHuman   :: OutputToHuman             -- ^ last words
                  -> IO () -- ^ the action to kick a chatter out
    , humanLeave  :: IO () -> IO () -- ^ the notif a user disconnected
    , toHuman     :: OutputToHuman             -- ^ some message
                  -> IO ()                     -- ^ the outlet
    , fromHuman   :: (InputFromHuman -> IO ()) -- ^ the intake
                  -> IO () -- ^ the intake installer
  }


-- * Adapt data structures between the chat world and the real world, in
-- this simple case, it's just some preliminary cmdl parsing on raw user 
-- input line, and string coercing

parseInputFromHuman :: InputFromHuman -> EdhValue
parseInputFromHuman raw = case T.stripPrefix "/" raw of
  Nothing   -> EdhString raw
  Just cmdl -> case T.words cmdl of
    cmd : args -> EdhPair (EdhString cmd) (EdhTuple $ EdhString <$> args)
    _          -> EdhString "/"

formatOutputToHuman :: EdhValue -> OutputToHuman
formatOutputToHuman = edhValueStr


-- | Connect chat world physics to the real world by pumping events in and out
adaptChatEvents :: ChatAccessPoint -> IO EventSink
adaptChatEvents !accessPoint = do
  evsAP <- atomically newEventSink
  accomodateAgent accessPoint $ \userAgent -> do
    evsIn  <- atomically newEventSink
    evsOut <- atomically newEventSink
    void $ forkIO $ evsToHuman evsOut userAgent
    fromHuman userAgent $ atomically . publishEvent evsIn . parseInputFromHuman
    humanLeave userAgent $ atomically $ publishEvent evsIn $ EdhPair
      -- generate a quit command on forceful disconnection
      (EdhString "quit")
      (EdhTuple [])
    -- show this new agent in to the chat world
    atomically
      $ publishEvent evsAP
      $ EdhArgsPack -- use an arguments-pack as event data
      $ ArgsPack    -- the data ctor
                 [EdhSink evsIn, EdhSink evsOut] -- positional args
                 Map.empty                       -- keyword args
  return evsAP
 where
  evsToHuman :: EventSink -> ChatUserAgent -> IO ()
  evsToHuman !evsOut !userAgent = do
    (!subChan, !ev1) <- atomically (subscribeEvents evsOut)
    let evToHuman !ev = case ev of
          (EdhPair EdhNil (EdhString lastWords)) ->
            -- this pattern from the world means chatter kicked
            cutoffHuman userAgent lastWords
          _ -> do
            toHuman userAgent $ formatOutputToHuman ev
            atomically (readTChan subChan) >>= evToHuman
    case ev1 of
      Just ev -> evToHuman ev
      Nothing -> atomically (readTChan subChan) >>= evToHuman


-- | Create a chat world and run it
runChatWorld :: ChatAccessPoint -> IO ()
runChatWorld !accessPoint = defaultEdhLogger >>= createEdhWorld >>= \world ->
  do
    installEdhBatteries world

    let withEdhErrorLogged :: Either InterpretError () -> IO ()
        withEdhErrorLogged = \case
          Left err -> atomically $ do
            rt <- readTMVar $ worldRuntime world
            runtimeLogger rt 50 Nothing
              $ ArgsPack [EdhString $ T.pack $ show err] Map.empty
          Right _ -> return ()

    (withEdhErrorLogged =<<) $ bootEdhModule world "chat" >>= \case
      Left  !err  -> return $ Left err
      Right !modu -> do
        moduCtx <- atomically $ moduleContext world modu
        evsAP   <- adaptChatEvents accessPoint
        (withEdhErrorLogged =<<) $ runEdhProgram moduCtx $ do
          pgs <- ask
          ctorRunCtrl evsAP $ \rcObj -> contEdhSTM $ do
            mthDismiss <- rcMethod pgs rcObj "dismiss"
            mthRun     <- rcMethod pgs rcObj "run"

            unsafeIOToSTM
              $ dismissAll accessPoint
              $ (withEdhErrorLogged =<<)
              $ runEdhProgram moduCtx
              $ do
                  pgs' <- ask
                  contEdhSTM $ rcRun pgs' rcObj mthDismiss

            rcRun pgs rcObj mthRun
        return $ Right ()

 where

  -- | All rc methods are nullary, can be called uniformly
  --
  -- This can be written in simpler non-CPS as we're not
  -- interested in the return value
  rcRun :: EdhProgState -> Object -> ProcDefi -> STM ()
  rcRun pgs rcObj mth'proc = runEdhProg pgs
    $ callEdhMethod (ArgsPack [] Map.empty) rcObj mth'proc Nothing edhNop

  -- | Get a method by name from rc object
  -- 
  -- This is done with simple TVar traversal, no need to go CPS
  rcMethod :: EdhProgState -> Object -> Text -> STM ProcDefi
  rcMethod pgs rcObj mthName =
    lookupEdhObjAttr rcObj (AttrByName mthName) >>= \case
      Nothing ->
        throwEdhSTM pgs EvalError
          $  "Method `RunCtrl."
          <> mthName
          <> "()` not defined in chat.edh ?"
      Just (EdhMethod mthVal) -> return mthVal
      Just malVal ->
        throwEdhSTM pgs EvalError
          $  "Unexpected `RunCtrl."
          <> mthName
          <> "()`, it should be a method but found to be a "
          <> T.pack (show $ edhTypeOf malVal)
          <> ": "
          <> T.pack (show malVal)

  -- | Construct the rc object
  --
  -- This has to be written in CPS to receive the return value from the
  -- class procedure written in Edh
  ctorRunCtrl :: EventSink -> (Object -> EdhProg (STM ())) -> EdhProg (STM ())
  ctorRunCtrl !evsAP !exit = do
    pgs <- ask
    let !ctx   = edh'context pgs
        !scope = contextScope ctx
    contEdhSTM $ lookupEdhCtxAttr scope (AttrByName "RunCtrl") >>= \case
      Nothing -> throwEdhSTM pgs EvalError "No `RunCtrl` defined in chat.edh ?"
      Just (EdhClass rcClass) ->
        runEdhProg pgs
          $ constructEdhObject (ArgsPack [EdhSink evsAP] Map.empty) rcClass
          $ \(OriginalValue !val _ _) -> case val of
              EdhObject rcObj -> exit rcObj
              _ ->
                throwEdh EvalError
                  $  "Expecting an object be constructed by `RunCtrl`, but got "
                  <> T.pack (show $ edhTypeOf val)
                  <> ": "
                  <> T.pack (show val)
      Just malVal ->
        throwEdhSTM pgs EvalError
          $ "Unexpected `RunCtrl` as defined in chat.edh, it should be a class but found to be a "
          <> T.pack (show $ edhTypeOf malVal)
          <> ": "
          <> T.pack (show malVal)
