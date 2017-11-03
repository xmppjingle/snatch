-module(snatch_router).
-compile([warnings_as_errors]).

-behaviour(snatch).

-export([init/1, handle_info/2, terminate/2]).

init([PID]) when is_pid(PID) ->
    {ok, PID}.

handle_info(Info, PID) ->
    PID ! Info,
    {noreply, PID}.

terminate(_Reason, _PID) ->
    ok.
