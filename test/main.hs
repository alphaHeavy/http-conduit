{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
import Test.Hspec.Monadic
import Test.Hspec.HUnit ()
import Test.HUnit
import Network.Wai
import Network.Wai.Handler.Warp (run)
import Network.HTTP.Conduit
import Control.Concurrent (forkIO, killThread)
import Network.HTTP.Types
import Control.Exception.Lifted (try, SomeException)
import Network.HTTP.Conduit.ConnInfo
import CookieTest (cookieTest)
import Data.Conduit.Network (runTCPServer, ServerSettings (..), HostPreference (HostAny))
import Data.Conduit (($$))
import Control.Monad.Trans.Resource (register)
import Control.Monad.IO.Class (liftIO)
import Data.Conduit.List (sourceList)

app :: Application
app req =
    case pathInfo req of
        [] -> return $ responseLBS status200 [] "homepage"
        _ -> return $ responseLBS status404 [] "not found"

main :: IO ()
main = hspecX $ do
    cookieTest
    describe "simpleHttp" $ do
        it "gets homepage" $ do
            tid <- forkIO $ run 3000 app
            lbs <- simpleHttp "http://localhost:3000/"
            killThread tid
            lbs @?= "homepage"
        it "throws exception on 404" $ do
            tid <- forkIO $ run 3001 app
            elbs <- try $ simpleHttp "http://localhost:3001/404"
            killThread tid
            case elbs of
                Left (_ :: SomeException) -> return ()
                Right _ -> error "Expected an exception"
    describe "manager" $ do
        it "closes all connections" $ do
            clearSocketsList
            tid1 <- forkIO $ run 3002 app
            tid2 <- forkIO $ run 3003 app
            withManager $ \manager -> do
                let Just req1 = parseUrl "http://localhost:3002/"
                let Just req2 = parseUrl "http://localhost:3003/"
                _res1a <- http req1 manager
                _res1b <- http req1 manager
                _res2 <- http req2 manager
                return ()
            requireAllSocketsClosed
            killThread tid2
            killThread tid1
    describe "DOS protection" $ do
        it "overlong headers" $ do
            tid1 <- forkIO overLongHeaders
            withManager $ \manager -> do
                _ <- register $ killThread tid1
                let Just req1 = parseUrl "http://localhost:3004/"
                res1 <- try $ http req1 manager
                case res1 of
                    Left e -> liftIO $ show (e :: SomeException) @?= show OverlongHeaders
                    _ -> error "Shouldn't have worked"

overLongHeaders :: IO ()
overLongHeaders = runTCPServer (ServerSettings 3004 HostAny) $ \_ sink ->
    src $$ sink
  where
    src = sourceList $ "HTTP/1.0 200 OK\r\nfoo: " : repeat "bar"
