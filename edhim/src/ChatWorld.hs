
-- | This module models an Edh world doing chat hosting business

module ChatWorld where

import           Prelude
-- import           Debug.Trace

import           Control.Monad.Reader

import           Control.Exception
import           Control.Concurrent
import           Control.Concurrent.STM

import           Data.Text                      ( Text )
import qualified Data.Text                     as T
import qualified Data.HashMap.Strict           as Map

import           Language.Edh.EHI


-- the Edh module name to be run as the console
consoleModule :: String
consoleModule = "chat"


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
    accomodateAgents :: (ChatUserAgent -> IO ()) -- ^ the entry
                     -> IO () -- ^ the blocking accomodate action
  }

-- | Joint physics of a user agent in a chat world
data ChatUserAgent = ChatUserAgent {
      cutoffHuman :: OutputToHuman             -- ^ last words
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
formatOutputToHuman (EdhString s) = s
formatOutputToHuman v             = T.pack $ show v


-- | Connect chat world physics to the real world by pumping events in and out
adaptChatEvents :: ChatAccessPoint -> EventSink -> IO ()
adaptChatEvents !accessPoint !evsAP =
  accomodateAgents accessPoint -- this blocks forever
    -- this function is invoked for each user connection
                               $ \userAgent -> do
    -- start a separate thread to pump msg from chat world to realworld
    evsOut <- forkEventConsumer $ \evsOut -> do
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
    -- wait until the chat world has started consuming events from `evsIn`
    evsIn <- waitEventConsumer $ \evsIn ->
      atomically
        $ publishEvent evsAP -- show this new agent in to the chat world
        $ EdhArgsPack -- use an arguments-pack as event data
        $ ArgsPack    -- the data ctor
                   [EdhSink evsIn, EdhSink evsOut] -- positional args
                   Map.empty                       -- keyword args
    -- now install `evsIn` as the drop target for each human input from realworld
    fromHuman userAgent $ atomically . publishEvent evsIn . parseInputFromHuman
    humanLeave userAgent $ atomically $ publishEvent evsIn $ EdhPair
      -- generate a quit command on forceful disconnection
      (EdhString "quit")
      (EdhTuple [])


-- | Create a chat world and run it
runChatWorld :: EdhConsole -> ChatAccessPoint -> IO ()
runChatWorld !console !accessPoint = do
  world <- createEdhWorld console
  installEdhBatteries world

  -- XXX here to install worshipped host modules and other artifacts

  -- the Chat demo is so simple that no host module/procedure is defined,
  -- we just grab event sinks defined by the Edh modules and work with
  -- them from the host side
  bizArts <- runEdhProgram (worldContext world) $ do
    pgs <- ask
    importEdhModule "chat/business" $ \(OriginalValue moduVal _ _) ->
      case moduVal of
        EdhObject modu ->
          contEdhSTM
            $   sequence
                  (   fmap edhUltimate
                  .   lookupEdhObjAttr pgs modu
                  .   AttrByName
                  <$> ["accessPoint", "running"]
                  )
            >>= \case
                  got@[EdhSink _evsAP, EdhSink _evsRunning] ->
                    haltEdhProgram $ EdhTuple got
                  _ -> throwEdhSTM
                    pgs
                    UsageError
                    "Missing accessPoint/running sink from chat/business module!"
        _ -> error "bug: importEdhModule returned non-object"

  -- fork the GHC thread to do event pumping
  void $ forkIO $ case bizArts of
    Left  err -> throwIO err
    Right (EdhTuple [EdhSink evsAP, EdhSink evsRunning]) -> do
      -- wait until the business has started running
      atomically (subscribeEvents evsRunning) >>= \(sr, maybeRunning) ->
        case maybeRunning of
          Just (EdhBool True) -> pure ()
          _                   -> atomically $ readTChan sr >>= \case
            EdhBool True -> return ()
            _            -> retry
      -- pump business events
      adaptChatEvents accessPoint evsAP
    _ -> throwIO $ EdhError UsageError "abnormal" $ EdhCallContext "<host>" []

  -- here being the host interpreter, we loop infinite runs of the Edh
  -- console REPL program, unless cleanly shutdown, for resilience
  let doneRightOrRebirth = runEdhModule world consoleModule >>= \case
    -- to run a module is to seek its `__main__.edh` and execute the
    -- code there in a volatile module context, it can import itself
    -- (i.e. `__init__.edh`) during the run. all imported modules can
    -- survive program crashes.
        Left !err -> do -- program crash on error
          atomically $ do
            consoleOut "Your program crashed with an error:\n"
            consoleOut $ T.pack $ show err <> "\n"
            -- the world with all modules ever imported, is still
            -- there, repeat another repl session with this world.
            -- it may not be a good idea, but just so so ...
            consoleOut "🐴🐴🐯🐯\n"
          doneRightOrRebirth
        Right !phv -> case edhUltimate phv of
          EdhNil -> atomically $ do
            -- clean program halt, all done
            consoleOut "Well done, bye.\n"
            consoleShutdown
          _ -> do -- unclean program exit
            atomically $ do
              consoleOut "Your program halted with a result:\n"
              consoleOut $ (<> "\n") $ case phv of
                EdhString msg -> msg
                _             -> T.pack $ show phv
            -- the world with all modules ever imported, is still
            -- there, repeat another repl session with this world.
            -- it may not be a good idea, but just so so ...
              consoleOut "🐴🐴🐯🐯\n"
            doneRightOrRebirth
  doneRightOrRebirth
 where
  consoleOut      = writeTQueue (consoleIO console) . ConsoleOut
  consoleShutdown = writeTQueue (consoleIO console) ConsoleShutdown
