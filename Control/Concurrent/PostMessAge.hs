
-- | Mechanism to get messages sent to a 'Handle' concurrently
--   without getting them mixed. They are sent to the handle in the same
--   order they are received by a /passer object/ (see 'Passer'), not
--   sending a message before the previous message is sent completely.
module Control.Concurrent.PostMessAge (
    -- * Passer type
    Passer
    -- * Open/Close a passer
  , createPasser
  , closePasser
    -- * Send messages to the passer
  , postMessage
    -- * Check passer status
  , isPasserClosed
  , isPasserOpen
  ) where

import Control.Monad (when,void)
import Control.Concurrent
import Control.Concurrent.MVar
import Control.Concurrent.Chan
import System.IO (Handle)

data PasserStatus = Open | Closed

-- | The 'Passer' is the object that you send the messages to.
--   It will redirect this message to its attached 'Handle',
--   making sure the messages are not intercalated.
--   Use 'postMessage' to send message to a passer object.
data Passer a = Passer
  { passerStatus  :: MVar PasserStatus
  , passerHandle  :: Handle
  , passerChannel :: Chan (Maybe a)
    }

-- | Passer object feeder loop.
feedHandle :: (Handle -> a -> IO ()) -> Passer a -> IO ()
feedHandle f p = loop
  where
    ch = passerChannel p
    h = passerHandle p
    loop = do
      mx <- readChan ch
      case mx of
        Nothing -> return ()
        Just x -> f h x >> loop

-- | Check if a passer object is closed. When a passer object
--   is closed, it won't send any more messages to its attached
--   handle. This does not mean the handle itself is closed.
isPasserClosed :: Passer a -> IO Bool
isPasserClosed p = do
  st <- readMVar $ passerStatus p
  return $ case st of
    Closed -> True
    _ -> False

-- | Check if a passer object is open. While a passer object
--   is open, all the messages received by the passer are
--   sent to its attached handle.
isPasserOpen :: Passer a -> IO Bool
isPasserOpen = fmap not . isPasserClosed

-- | Send a message to a passer object. It returns a value
--   indicating if the message reached the passer object.
postMessage :: Passer a -> a -> IO Bool
postMessage p x = do
  b <- isPasserOpen p
  when b $ writeChan (passerChannel p) $ Just x
  return b

-- | Close a passer object, so it won't receive any more messages
--   in the future. Once a passer object is closed, it can't be
--   opened again. If you want to reuse a handle, create another
--   passer object with 'createPasser'.
closePasser :: Passer a -> IO ()
closePasser p = do
  st <- swapMVar (passerStatus p) Closed
  case st of
    Closed -> return ()
    Open -> writeChan (passerChannel p) Nothing

-- | Create a passer object from a 'Handle' and a function to send
--   values to that handle.
createPasser :: Handle -- ^ Handle to use
             -> (Handle -> a -> IO ()) -- Put Handle operation
             -> IO (Passer a)
createPasser h f = do
  stv <- newMVar Open
  ch <- newChan
  let p = Passer stv h ch
  _ <- forkIO $ feedHandle f p
  return p
