resource "eval_skyadmin"
version "1.0.0"
auto_start true

-- world.environment : Open77.environment.setTime / setWeather / getState
-- acl.read          : Open77.acl.isAllowed (in-handler recheck of command.<name>)
permissions { "world.environment", "acl.read" }

server_script "server/main.lua"
