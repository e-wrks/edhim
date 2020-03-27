
-- | This module models an Edh world doing chat hosting business

module ChatWorld where

import           Prelude
-- import           Debug.Trace

import           GHC.Conc                       ( unsafeIOToSTM )

import           Control.Monad.Reader

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
runChatWorld :: EdhRuntime -> ChatAccessPoint -> IO ()
runChatWorld !runtime !accessPoint = do
  world <- createEdhWorld runtime
  installEdhBatteries world

  -- TODO obtain the signals from 'chat/business' module,
  --  * get `accessPoint` `running`,
  --  * wait until running is flagged true,
  --  * call `adaptChatEvents` 
  let evsAP :: EventSink = undefined

  adaptChatEvents accessPoint evsAP

  runEdhModule world "chat" >>= \case
    Left  !err -> atomically $ writeTQueue ioQ $ ConsoleOut $ T.pack $ show err
    Right phv  -> case edhUltimate phv of
      EdhNil -> pure () -- clean program halt, all done
      _      -> -- unclean program exit
                atomically $ writeTQueue ioQ $ ConsoleOut $ case phv of
        EdhString msg -> msg
        _             -> T.pack $ show phv
  where ioQ = consoleIO runtime
