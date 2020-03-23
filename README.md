# EdhIm - Đ (Edh) doing Instant Messaging

[![Gitter](https://badges.gitter.im/e-wrks/community.svg)](https://gitter.im/e-wrks/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

This is a project demonstrating a few sweet spots found balanced between
_declarative_ and _imperative_ stylish, when put together, can make
[**Đ (Edh)**](https://github.com/e-wrks/edh)
code even more concise than **Haskell** code.

This repository can be used as the scaffold to start a **Haskell** +
**Edh** software project, as well as to run the demo for some feels.

**Đ (Edh)** code should be especially more _readable_/_modifiable_
to average people without a
[functional](https://github.com/e-wrks/edh#functional---try-not-to-abuse-this-concept)
mindset (yet), thus development of a software project in **Haskell** + **Edh**
can be more viable and maintainable by teams with diversified crew members.

One possible division of labour on from this repository as a baseline, e.g.

- Junior people and New Comers (the Dev), End Users (bugfixers):

  Extend [Đ (Edh) code](#full-%c4%90-edh-code-95-loc) with new modules,
  3rd party packages for application / business logics, with fast
  iterations

- Thinkist people:

  Establish the
  [world modeling code](#world-modeling-code-in-haskell-190-loc),
  then progressively (but may better conservatively) improve the models,
  for mistakes harder to be made, idiomatics easier to be followed

- Architect / Senior Engineering people, Security Experts, the Ops:

  Establish and maintain
  [world reifying code](#world-reifying-code-in-haskell-193-loc),
  ensure the systems run continuously & securely on a foundation of
  contemporary technology stack, deal with dependency EOLs, patch CVEs in
  time, perform regularly the house keeping of backing storage

- [Quick Start](#quick-start)
  - [Favouring Cabal](#favouring-cabal)
  - [Favouring Stack](#favouring-stack)
- [TL;DR](#tldr)
  - [Screenshots](#screenshots)
- [All the 3 source files](#all-the-3-source-files)
  - [Full Đ (Edh) code (80 LoC)](#full-%c4%90-edh-code-80-loc)
  - [World modeling code in Haskell (140 LoC)](#world-modeling-code-in-haskell-140-loc)
  - [World reifying code in Haskell (190 LoC)](#world-reifying-code-in-haskell-190-loc)

## Quick Start

```shell
curl -L https://github.com/e-wrks/edhim/archive/master.tar.gz | tar xzf -
mv edhim-master my-awsome-project
cd my-awsome-project
```

### Favouring [Cabal](https://www.haskell.org/cabal)

```shell
export EDH_LOG_LEVEL=DEBUG
cabal v2-run edhim:edhim
```

### Favouring [Stack](https://haskellstack.org)

```shell
export EDH_LOG_LEVEL=DEBUG
stack run
```

## TL;DR

The usecase is the same as the
[Chat Example](https://github.com/simonmar/par-tutorial/blob/master/code/chat/Main.hs)
in Simon Marlow's classic book
[Parallel and Concurrent Programming with Haskell](https://simonmar.github.io/pages/pcph.html)

**EdhIm** talks through
[WebScokets](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API)
so you use a web browser instead of
[cli](https://en.wikipedia.org/wiki/Command-line_interface)
to do chatting.

### Screenshots

![edhim-demo-alice](https://user-images.githubusercontent.com/15646573/72426593-fd3d6b80-37c4-11ea-8e7d-bd8a1ec9e450.png)
![edhim-demo-bob](https://user-images.githubusercontent.com/15646573/72426594-fd3d6b80-37c4-11ea-873b-1a920e9b75c5.png)
![edhim-demo-console](https://user-images.githubusercontent.com/15646573/72426596-fd3d6b80-37c4-11ea-9339-10b9440911c4.png)

## All the 3 source files

### Full Đ (Edh) code (80 LoC)

https://github.com/e-wrks/edhim/blob/master/edh_modules/chat.edh

```haskell
# this ctor bootstraps the chat world
class RunCtrl {
  method __init__ (accessPoint as this.accessPoint) pass

  chatters = {,}  # the dict of all chatters by name

  method dismiss () {  # this is called on Ctrl^C at the console
    runtime.info <| 'Dismissing all active chatters'
    ai {  # use a tx, don't get a racing joining chatter lost/leaked
      committee = this.chatters
      this.chatters = {,}
    }
    for (_name, chatter) from committee do if chatter!=nil then
      chatter.kicked <- 'server purge'
  }

  # this ctor allocates a private namespace (object) for a new user session
  class Chat {

    kicked = sink  # create a new sink for kicked-out event

    reactor kicked reason {
      runtime.debug <| 'Done with ' ++name++ ' - ' ++reason
      # posting a nil:<str> pair as the msg out, to trigger `cutoffHuman`
      # mechanism defined for the agency model
      out <- nil: if reason != nil
        then "You have been kicked: " ++ reason
        else ''
      break  # `break` from a reactor breaks the thread, 'Chat' then stops
    }

    method __init__ (
      incoming as this.incoming, out as this.out,
    ) {
      this.name = '<stranger>'  # to appear in the log on premature disconnection
      out <- "What is your name?"
      for name from incoming do case type(name) of {
        StringType -> {
          this.name = name
          # use a tx to mediate naming contentions
          ai case chatters[name] of nil -> {
            chatters[name] = this
            break  # to break the for-from-do loop
          }
          out <- "The name " ++name++ " is in use, please choose another"
          # not doing fallthrough here, the loop will continue
        }
        # abnormal input for name, this chatter is destined to be kicked out
        kicked <- case name of {
          { cmd:_ } -> case cmd of {
            'quit' -> nil  # human left without answering the name
            fallthrough  # other malicious cmds
          }
          runtime.warn <| 'Some one tried to use name: ' ++ name
          'misbehaving, adversarial name - ' ++ name
        }
      }

      defer {  # defered code is guaranteed to run on thread termination
        runtime.debug <| 'Cleaning up for ' ++ name
        # need a tx to not cleanup a later live chatter with same name
        ai if chatters[name] == this then chatters[name] = nil
      }

      # here is a tiny window for user msgs through `incoming` get dropped,
      # that between the subscription loop below and the name prompting loop
      # above. this is not a big deal for our chat business, left as a demo.
      for msg from incoming do case msg of {

        # the mre (most-recent-event) from `incoming` atm tends to be the
        # user's answer to name inquiry, it's very probably be the very first
        # `msg` seen here, we take this chance to greet the user.
        # well this handling may surprise the user when later he/she typed
        # his/her own name, intending to send as a broadcast message.
        name -> out <- ' 🎉 Welcome ' ++ name ++ '!'

        { cmd:args } -> case cmd of {

          'kick' -> case args of { { (who,) } -> case chatters[who] of {
            nil -> out <- who ++ ' is not connected'
            { chatter } -> {
              chatter.kicked <- 'by ' ++ this.name
              out <- 'you kicked ' ++ who
            }
          } out <- 'Invalid args to /kick: ' ++ args }

          'tell' -> case args of { { (who, what) } -> case chatters[who] of {
            nil -> out <- who ++ ' is not connected'
            { chatter } -> chatter.out <- '*'++name++'*: ' ++ what
          } out <- 'Invalid args to /tell: ' ++ args }

          'quit' -> { out <- nil:'Bye!'; kicked <- nil }

          out <- 'Unrecognised command: ' ++ msg
        }

        # run to here means none of the branches above matched, so it's a public
        # message and let's broadcast it
        # it's okay to use a snapshot of all live chatters, no tx here
        for (_name, chatter) from chatters do if chatter!=nil then
          chatter.out <- '<'++ this.name ++'>: ' ++ msg

      }
    }

  }

  method run () { # this is the method to keep the world running
    # each time a new agent enters the chat world, a pair of sinks for its
    # incoming and outgoing messages are posted through the sink of access point
    for (in, out) from accessPoint do {
      go Chat(in, out)  # start a chatter thread to do the IO
      in=nil out=nil  # unref so they're garbage-collectable after chatter left
    }
  }
}
```

### World modeling code in Haskell (140 LoC)

https://github.com/e-wrks/edhim/blob/master/edhim/src/ChatWorld.hs

```haskell
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
      dismissAll :: IO () -- ^ the action to kick all chatters out
                 -> IO () -- ^ the action installer
    , accomodateAgents :: (ChatUserAgent -> IO ()) -- ^ the entry
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
runChatWorld :: ChatAccessPoint -> IO ()
runChatWorld !accessPoint = defaultEdhRuntime >>= createEdhWorld >>= \world ->
  do
    installEdhBatteries world

    let withEdhLogged :: Either EdhError () -> IO ()
        withEdhLogged result = do
          case result of
            Left err -> atomically $ logger 50 (Just "<the-hell>") $ ArgsPack
              [EdhString $ T.pack $ show err]
              Map.empty
            Right _ -> pure ()
          flushLogs
          where EdhRuntime logger _ flushLogs = worldRuntime world

    (withEdhLogged =<<) $ bootEdhModule world "chat" >>= \case
      Left  !err  -> return $ Left err
      Right !modu -> do
        let !moduCtx = moduleContext world modu
        -- the event producing will not start until `evsAP` is subscribed from
        -- the chat world
        evsAP <- forkEventProducer $ adaptChatEvents accessPoint
        (withEdhLogged =<<) $ runEdhProgram moduCtx $ do
          pgs <- ask
          ctorRunCtrl evsAP $ \rcObj -> contEdhSTM $ do
            mthDismiss <- rcMethod pgs rcObj "dismiss"
            mthRun     <- rcMethod pgs rcObj "run"

            unsafeIOToSTM
              $ dismissAll accessPoint
              $ (withEdhLogged =<<)
              $ runEdhProgram moduCtx
              $ do
                  pgs' <- ask
                  contEdhSTM $ runEdhProg pgs' $ callEdhMethod
                    rcObj
                    mthDismiss
                    (ArgsPack [] Map.empty)
                    edhEndOfProc

            runEdhProg pgs $ callEdhMethod rcObj
                                           mthRun
                                           (ArgsPack [] Map.empty)
                                           edhEndOfProc
        return $ Right ()

 where

  -- | Get a method by name from rc object
  --
  -- This is done with simple TVar traversal, no need to go CPS
  rcMethod :: EdhProgState -> Object -> Text -> STM ProcDefi
  rcMethod pgs rcObj mthName =
    lookupEdhObjAttr pgs rcObj (AttrByName mthName) >>= \case
      EdhNil ->
        throwEdhSTM pgs EvalError
          $  "Method `RunCtrl."
          <> mthName
          <> "()` not defined in chat.edh ?"
      EdhMethod mthVal -> return mthVal
      malVal ->
        throwEdhSTM pgs EvalError
          $  "Unexpected `RunCtrl."
          <> mthName
          <> "()`, it should be a method but found to be a "
          <> T.pack (edhTypeNameOf malVal)

  -- | Construct the rc object
  --
  -- This has to be written in CPS to receive the return value from the
  -- class procedure written in Edh
  ctorRunCtrl :: EventSink -> (Object -> EdhProg (STM ())) -> EdhProg (STM ())
  ctorRunCtrl !evsAP !exit = do
    pgs <- ask
    let !ctx   = edh'context pgs
        !scope = contextScope ctx
    contEdhSTM $ lookupEdhCtxAttr pgs scope (AttrByName "RunCtrl") >>= \case
      EdhNil -> throwEdhSTM pgs EvalError "No `RunCtrl` defined in chat.edh ?"
      EdhClass rcClass ->
        runEdhProg pgs
          $ constructEdhObject rcClass (ArgsPack [EdhSink evsAP] Map.empty)
          $ \(OriginalValue !val _ _) -> case val of
              EdhObject rcObj -> exit rcObj
              _ ->
                throwEdh EvalError
                  $ "Expecting an object be constructed by `RunCtrl`, but got a "
                  <> T.pack (edhTypeNameOf val)
      malVal ->
        throwEdhSTM pgs EvalError
          $ "Unexpected `RunCtrl` as defined in chat.edh, it should be a class but found to be a "
          <> T.pack (edhTypeNameOf malVal)
```

### World reifying code in Haskell (190 LoC)

https://github.com/e-wrks/edhim/blob/master/edhim/src/Main.hs

```haskell
{-# LANGUAGE QuasiQuotes #-}

-- | This main module further reifies the modeled Edh world
-- from 'ChatWorld' to run upon a technology stack at present
-- (year 2020), i.e.
--  *) POSIX
--    *) process w/ signals
--    *) network sockets
--  *) the websockets toolkit
--  *) the Snap http server
--  *) HTML5 browser client
--    *) CSS
--    *) JavaScript
--    *) WebSockets

module Main
  ( main
  )
where

import           Prelude
import           Debug.Trace

import           System.IO                      ( stderr )

import           System.Clock

import           Control.Exception
import           Control.Monad
import           Control.Concurrent
import           System.Posix.Signals

import           Data.IORef
import           Data.Text.IO
import           Data.Text                      ( Text )
import qualified Data.Text                     as T
import qualified Data.Text.Lazy                as TL
import           Data.Text.Encoding

import qualified Data.ByteString.Char8         as B
import qualified Data.ByteString.Lazy          as BL

import           Network.Socket
import qualified Network.WebSockets            as WS

import qualified Snap.Core                     as Snap
import qualified Snap.Http.Server              as Snap

import           NeatInterpolation

import           ChatWorld


servAddr = "0.0.0.0"
wsPort = 8687
httpPort = 8688

servAddr :: Text
wsPort, httpPort :: Int

servWebSockets :: (ChatUserAgent -> IO ()) -> IO ()
servWebSockets !agentEntry = do
  let acceptWSC sock = do
        (conn, _) <- accept sock
        void $ forkFinally (handleWSC conn) $ \wsResult -> do
          case wsResult of
            Left  exc -> consoleLog $ "WS error: " <> T.pack (show exc)
            Right _   -> pure ()
          close conn -- close the socket anyway
        acceptWSC sock -- tail recursion

      handleWSC conn = do
        pconn <- WS.makePendingConnection conn
          $ WS.defaultConnectionOptions { WS.connectionStrictUnicode = True }
        wsc             <- WS.acceptRequest pconn
        disconnectNotif <- newEmptyMVar
        incomingMsg     <- newEmptyMVar
        let cutOff :: Text -> IO ()
            cutOff !lastWords = handle noPanic $ do
              WS.sendTextData wsc lastWords
              WS.sendClose wsc lastWords
            sendOut :: Text -> IO ()
            sendOut = handle noPanic . WS.sendTextData wsc
            noPanic :: SomeException -> IO ()
            noPanic exc = trace ("WS unexpected: " <> show exc) $ return ()

            keepReadingPkt = do
              pkt <- WS.receiveDataMessage wsc
              case pkt of
                (WS.Text _bytes (Just pktText)) ->
                  tryReadMVar incomingMsg >>= \case
                    Nothing -> consoleLog $ "WS got: " <> TL.toStrict pktText
                    Just !msgSink -> msgSink (TL.toStrict pktText)
                (WS.Binary _bytes) -> WS.sendCloseCode wsc 1003 ("?!?" :: Text)
                _                  -> WS.sendCloseCode wsc 1003 ("!?!" :: Text)
    -- https://hackage.haskell.org/package/websockets/docs/Network-WebSockets.html#v:sendCloseCode
    -- > you should continue calling receiveDataMessage until you receive a CloseRequest exception.
              keepReadingPkt

        agentEntry ChatUserAgent { cutoffHuman = cutOff
                                 , humanLeave  = putMVar disconnectNotif
                                 , toHuman     = sendOut
                                 , fromHuman   = putMVar incomingMsg
                                 }

        keepReadingPkt `catch` \case
          WS.CloseRequest closeCode closeReason ->
            if closeCode == 1000 || closeCode == 1001
              then pure ()
              else
                consoleLog
                $  "WS closed with code "
                <> T.pack (show closeCode)
                <> " and reason ["
                <> decodeUtf8 (BL.toStrict closeReason)
                <> "]"
          WS.ConnectionClosed -> consoleLog "WS disconnected"
          _                   -> consoleLog "WS unexpected error"

        -- notify the world anyway
        tryReadMVar disconnectNotif >>= sequence_

  withSocketsDo $ do
    addr <- resolveWsAddr
    bracket (open addr) close acceptWSC

 where
  resolveWsAddr = do
    let hints =
          defaultHints { addrFlags = [AI_PASSIVE], addrSocketType = Stream }
    addr : _ <- getAddrInfo (Just hints)
                            (Just $ T.unpack servAddr)
                            (Just (show wsPort))
    return addr
  open addr = do
    sock <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
    setSocketOption sock ReuseAddr 1
    bind sock (addrAddress addr)
    listen sock 10
    return sock


-- | Triple Ctrl^C to kill the server; double Ctrl^C to quit the server;
-- single Ctrl^C to dismiss all atm, i.e. a server purge.
handleCtrlC :: IO () -> IO ()
handleCtrlC !serverPurge = do
  mainThId          <- myThreadId
  cccVar            <- newIORef (0 :: Int) -- Ctrl^C Count
  lastInterruptTime <- (sec <$> getTime Monotonic) >>= newIORef
  let onCtrlC = do
        lastSec <- readIORef lastInterruptTime
        nowSec  <- sec <$> getTime Monotonic
        writeIORef lastInterruptTime nowSec
        if nowSec - lastSec < 2 -- count quickly repeated Ctrl^C clicks
          then modifyIORef' cccVar (+ 1)
          else writeIORef cccVar 1
        ccc <- readIORef cccVar
        if ccc >= 3 -- tripple click
          then killThread mainThId
          else if ccc >= 2 -- double click
            then throwTo mainThId UserInterrupt
            else -- single click
                 serverPurge
  void $ installHandler keyboardSignal (Catch onCtrlC) Nothing


main :: IO ()
main = do
  void $ forkIO $ Snap.httpServe httpCfg $ Snap.path "" $ do
    Snap.modifyResponse $ Snap.setContentType "text/html; charset=utf-8"
    Snap.writeText html

  -- we're handling Ctrl^C below for server purge action in the chat world,
  -- it needs to run from the main thread, so snap http is forked to a side
  -- thread above.

  runChatWorld $ ChatAccessPoint handleCtrlC servWebSockets

 where

  !httpCfg =
    Snap.setBind (encodeUtf8 servAddr)
      $ Snap.setPort httpPort
      $ Snap.setStartupHook httpListening
      $ Snap.setVerbose False
      $ Snap.setAccessLog Snap.ConfigNoLog
      $ Snap.setErrorLog (Snap.ConfigIoLog $ B.hPutStrLn stderr) mempty
  httpListening httpInfo = do
    listenAddrs <- sequence (getSocketName <$> Snap.getStartupSockets httpInfo)
    consoleLog $ "Đ - Im available at: " <> T.unwords
      (("http://" <>) . T.pack . show <$> listenAddrs)

  !(wsSuffix :: Text) = ":" <> T.pack (show wsPort)

  -- html5 source for the single page app
  !html = [text|
<title>Đ (Edh) Im</title>
<h3>Đ doing Instant Messaging
<span style="float: right; font-size: 60%;">
<a target="_blank" href="https://github.com/e-wrks/edhim">source</a></span>
</h3>

<div id="msg"></div>
<input id="keyin" type="text" autofocus/>
<style>
  #msg { width: 90%; height: 60%; overflow: scroll; }
  #msg>div { padding: 3pt 6pt; border: solid silver 1px; }
  #keyin { margin: 6pt 3pt; width: 68%; }
</style>
<script type="module">
  const msgDiv = document.getElementById('msg')
  const keyinBox = document.getElementById('keyin')
  const ws = new WebSocket("ws://" + location.hostname + "${wsSuffix}")

  ws.onmessage = me => {
    if ("string" !== typeof me.data) {
      debugger;
      throw "WS msg of type " + typeof me.data + " ?!";
    }
    let msgPane = document.createElement('pre')
    msgPane.appendChild(document.createTextNode(me.data))
    let msgRecord = document.createElement('div')
    msgRecord.appendChild(document.createTextNode('💬 ' + new Date()))
    msgRecord.appendChild(msgPane)
    msgDiv.appendChild(msgRecord)
    msgDiv.scrollTop = msgDiv.scrollHeight
  }

  keyinBox.addEventListener('keydown', function onEvent(evt) {
    if (evt.key === "Enter") {
      if(ws.readyState !== WebSocket.OPEN) {
        alert(
          `You've probably been kicked out already!
Refresh the page to reconnect.`)
        return false
      }
      ws.send(keyinBox.value)
      keyinBox.value = ''
      return false
    }
  })
</script>
|]


consoleLog :: Text -> IO ()
consoleLog = hPutStrLn stderr
```
