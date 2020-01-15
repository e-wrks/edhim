{-# LANGUAGE QuasiQuotes #-}

module Main
  ( main
  )
where

import           Prelude
import           Debug.Trace

import           System.IO                      ( stderr
                                                , hPutStrLn
                                                )

import           System.Clock

import           Control.Exception
import           Control.Monad
import           Control.Concurrent
import           System.Posix.Signals

import           Data.IORef
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

