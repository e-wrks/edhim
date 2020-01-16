# EdhIm - Đ (Edh) doing Instant Messaging

This is a project demonstrating a few sweet spots found balanced between
_declarative_ and _imperative_ stylish, when put together, can make
[**Đ (Edh)**](https://github.com/e-wrks/edh)
code even more concise than **Haskell** code.

**Đ (Edh)** code should be especially more _readable_/_modifiable_
to average people without a
[functional](https://github.com/e-wrks/edh#functional---try-not-to-abuse-this-concept)
mindset, thus more maintainable by teams with diversified crew members.

This repository can be used as the scaffold to start your **Haskell** +
**Edh** software development, as well as to run the demo yourself.

- [Quick Start](#quick-start)
  - [Favouring Cabal](#favouring-cabal)
  - [Favouring Stack](#favouring-stack)
- [TL;DR](#tldr)
  - [Screenshots](#screenshots)
  - [Full Đ (Edh) Code](#full-%c4%90-edh-code)
  - [World modeling code in Haskell](#world-modeling-code-in-haskell)
  - [World reifying code in Haskell](#world-reifying-code-in-haskell)

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

### Full Đ (Edh) Code

**95 LoC**
https://github.com/e-wrks/edhim/blob/master/edh_modules/chat.edh

```haskell
# this ctor bootstraps the chat world
class RunCtrl accessPoint {
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

  class Chat (incoming, out) {
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

    name = '<stranger>'  # to appear in the log on premature disconnection
    out <- "What is your name?"
    for name from incoming do case type(name) of {
      StringType -> {
        # use a tx to mediate naming contentions
        ai case chatters[name] of nil -> {
          chatters[name] = this
          break  # to break the for-from-do loop
        }
        out <- "The name " ++name++ " is in use, please choose another"
        # not doing fallthrough here, the loop will continue
      }
      # this chatter is destined to be kicked out, if reaching here
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

    for msg from incoming do case msg of {
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
        chatter.out <- '<'++name++'>: ' ++ msg
    }
  }

  method run ()  # this is the method to keep the world running
    # each time a new agent enters the chat world, a pair of sinks for its
    # incoming and outgoing messages are posted through the sink of access point
    for (in, out) from accessPoint do {
      go Chat(in, out)  # start a chatter thread to do the IO
      in=nil out=nil  # unref so they're garbage-collectable after chatter left
    }
}
```

### World modeling code in Haskell

**190 LoC excluding imports**
https://github.com/e-wrks/edhim/blob/master/edhim/src/ChatWorld.hs

```haskell
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
  rcRun :: EdhProgState -> Object -> Method -> STM ()
  rcRun pgs rcObj (Method mth'lexi'stack mth'proc) =
    runEdhProg pgs $ callEdhMethod (ArgsPack [] Map.empty)
                                   rcObj
                                   mth'lexi'stack
                                   mth'proc
                                   Nothing
                                   edhNop

  -- | Get a method by name from rc object
  --
  -- This is done with simple TVar traversal, no need to go CPS
  rcMethod :: EdhProgState -> Object -> Text -> STM Method
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
```

### World reifying code in Haskell

197 LoC excluding imports
https://github.com/e-wrks/edhim/blob/master/edhim/src/Main.hs

```haskell
servAddr = "0.0.0.0"
wsPort = 8687
httpPort = 8688

servAddr :: Text
wsPort, httpPort :: Int

servWebSockets :: IO ()
servWebSockets = runChatWorld $ ChatAccessPoint handleCtrlC $ \agentEntry -> do
  let
    acceptWSC sock = do
      (conn, _) <- accept sock
      void $ forkFinally (handleWSC conn) $ \wsResult -> do
        case wsResult of
          Left  exc -> consoleLog $ "WS error: " <> show exc
          Right _   -> pure ()
        close conn -- close the socket anyway
      acceptWSC sock -- tail recursion

    handleWSC conn = do
      pconn <- WS.makePendingConnection conn
        $ WS.defaultConnectionOptions { WS.connectionStrictUnicode = True }
      wsc             <- WS.acceptRequest pconn
      disconnectNotif <- newEmptyMVar
      incomingMsg     <- newEmptyMVar
      let
        cutOff :: Text -> IO ()
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
                Nothing ->
                  consoleLog $ "WS got: " <> T.unpack (TL.toStrict pktText)
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
              <> show closeCode
              <> " and reason ["
              <> T.unpack (decodeUtf8 $ BL.toStrict closeReason)
              <> "]"
        WS.ConnectionClosed -> consoleLog "WS disconnected"
        _                   -> consoleLog "WS unexpected error"

      -- notify the world anyway
      tryReadMVar disconnectNotif >>= sequence_

  void $ forkIO $ withSocketsDo $ do
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
  -- thread above

  servWebSockets

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
    consoleLog $ "Đ - Im available at: " <> unwords
      (("http://" <>) . show <$> listenAddrs)

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


consoleLog :: String -> IO ()
consoleLog = hPutStrLn stderr
```
