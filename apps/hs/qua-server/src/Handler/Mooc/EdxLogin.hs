{-# OPTIONS_HADDOCK hide, prune #-}
{-# LANGUAGE Rank2Types#-}
module Handler.Mooc.EdxLogin
  ( authLtiPlugin, dispatchLti
  ) where

import Import.NoFoundation
import Web.LTI

import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Control.Monad.Trans.Except (runExceptT)
import qualified Data.Map.Strict as Map

pluginName :: Text
pluginName = "lti"

authLtiPlugin :: (Yesod m, YesodAuth m) => LTIProvider -> AuthPlugin m
authLtiPlugin conf =
  AuthPlugin pluginName (dispatchAuth conf) $ \_tp -> return ()

-- | This creates a page with url
--   root.root/auth/page/lti/login
dispatchAuth :: (RenderMessage site FormMessage) => LTIProvider -> Text -> [Text] -> AuthHandler site TypedContent
dispatchAuth conf "POST" ["login"] = getRequest >>= lift . dispatchLti conf
dispatchAuth _ _ _                 = notFound



-- | This creates a page with url
--   root.root/auth/page/lti/login
dispatchLti :: (RenderMessage site FormMessage, YesodAuth site) => LTIProvider -> YesodRequest -> HandlerT site IO TypedContent
dispatchLti conf yreq = do
    clearSession
    eltiRequest <- runExceptT $ processYesodRequest conf yreq
    case eltiRequest of
      Left (LTIException err) -> permissionDenied $ Text.pack err
      Left (LTIOAuthException err) -> permissionDenied $ Text.pack $ show err
      Right msg -> do
        user_id                 <- lookupParam msg "user_id"
        resource_link_id        <- lookupParam msg "resource_link_id"
        context_id              <- lookupParam msg "context_id"
        lis_outcome_service_url <- lookupParamM msg "lis_outcome_service_url"
        lis_result_sourcedid    <- lookupParamM msg "lis_result_sourcedid"
        -- set LTI credentials
        setCredsRedirect
             . Creds pluginName user_id
             $ ("resource_link_id"       , resource_link_id)
             : ("context_id"             , context_id)
             : catMaybes
                [ (,) "lis_outcome_service_url" <$> lis_outcome_service_url
                , (,) "lis_result_sourcedid" <$> lis_result_sourcedid
                ]
             ++ saveCustomParams (Map.toList msg)
  where
    -- try to get essential edxParameters
    lookupParam msg p = case Map.lookup p msg of
                        Just v -> return $ Text.decodeUtf8 v
                        Nothing -> permissionDenied $ "Cannot access request parameter " <> Text.decodeUtf8 p
    -- try to get optional edxParameters
    lookupParamM msg p = return $ Text.decodeUtf8 <$> Map.lookup p msg
    -- store all special parameters in user session
    saveCustomParams [] = []
    saveCustomParams ((k,v):xs) = if "custom_" `isPrefixOf` k
               then (Text.decodeUtf8 k, Text.decodeUtf8 v) : saveCustomParams xs
               else saveCustomParams xs
