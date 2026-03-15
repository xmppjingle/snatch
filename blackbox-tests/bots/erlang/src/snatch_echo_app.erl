-module(snatch_echo_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    snatch_echo_sup:start_link().

stop(_State) ->
    ok.
