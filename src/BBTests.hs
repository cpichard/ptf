{-# LANGUAGE OverloadedStrings, TypeSynonymInstances, FlexibleInstances #-}
{-# OPTIONS_GHC -F -pgmF htfpp #-}
module BBTests where

import Test.Framework
import Test.Framework.TestTypes
import Test.Framework.BlackBoxTest
import Data.Yaml
import Data.Aeson.Types
import Control.Applicative
import System.Process
import System.Environment
import System.IO

data BBTestUnit =
  BBTestUnit
    { progName :: String -- name of the program under test
    , path :: String     -- ???
    , suffix :: String -- filename suffix for input file
    , verbose :: Bool -- verbosity
    } deriving Show

data BBTestSuite = 
  BBTestSuite
    { suiteName :: String
    , envCmd :: [String] -- Command to start the environment
    , tests :: [BBTestUnit] -- list of tests to build
    } deriving Show

instance FromJSON BBTestUnit where
    parseJSON (Object m) = 
            BBTestUnit <$> m .: "progName" 
                       <*> m .: "path" 
                       <*> m .: "suffix"
                       <*> m .: "verbose"
    parseJSON invalid    = typeMismatch "BBTestUnit" invalid

instance ToJSON BBTestUnit where
    toJSON (BBTestUnit n p s v) = object ["progName" .= n, "path" .= p, "suffix" .= s, "verbose" .= v]

instance FromJSON BBTestSuite where
    parseJSON (Object m) = BBTestSuite <$> m .: "suiteName" <*> m .: "envCmd" <*> m .: "tests"
    parseJSON invalid    = typeMismatch "BBTestSuite" invalid

instance ToJSON BBTestSuite where
    toJSON (BBTestSuite p e t)  = object [ "suiteName" .= p, "envCmd" .= e, "tests" .= t] 

-- Write a simple example file
writeExampleFile = do
  let bbtu1 = BBTestUnit "ls" "examples/sk_tests/ls" ".sh" True
      bbtu2 = BBTestUnit "ls" "examples/sk_tests/ls2" ".sh" True
      bbts = BBTestSuite "ls_test" ["bash"] [bbtu1, bbtu2]
  encodeFile "examples/example1.yaml" [bbts, bbts]


buildTestSuite :: String -> [BBTestUnit] -> [Test] -> IO TestSuite
buildTestSuite name (x:xs) tests = do
    newTest <- blackBoxTests (path x) (progName x) (suffix x) defaultBBTArgs
    buildTestSuite name xs (tests ++ newTest)
buildTestSuite name [] tests = return $ makeTestSuite name tests
    

runSuites :: [BBTestSuite] -> IO ()
runSuites (x:xs) = do
  putStrLn "running suites"
  thisExePath <- getExecutablePath
  (testUnit, hTestUnit) <- openTempFile "/tmp" "testunit.yaml" -- FIXME delete temp file 
  encodeFile testUnit (tests x)
  let command = [thisExePath] ++ [suiteName x] ++ [testUnit]
  let env = (envCmd x)
  (Just hin, _, _, p) <- createProcess (proc (head env) (tail env)) {std_in = CreatePipe}
  putStrLn $ "loading environment " ++ (show env)
  putStrLn $ "running " ++ (show command)
  -- TODO send command to process
  hPutStrLn hin (showCommandForUser (head command) (tail command))
  waitForProcess p
  putStrLn $ "leaving environment" 
  runSuites xs
runSuites [] = putStrLn "all suite processed"