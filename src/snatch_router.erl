-module(snatch_router).
-compile([warnings_as_errors]).

-behaviour(snatch).

-export([init/1, handle_info/2, terminate/2]).

-spec init([pid() | atom()]) -> {ok, pid() | atom()}.
init([undefined]) ->
    erlang:error(badarg);
init([Name]) when is_atom(Name) ->
    LocatedPID = whereis(Name),
    lager:debug("Located PID: ~p from Name: ~p", [LocatedPID, Name]),
    {ok, LocatedPID};
init([PID]) when is_pid(PID) ->
    {ok, PID}.

-spec handle_info(Info :: term(), pid() | atom()) ->
      {noreply, pid() | atom()}.
handle_info(Info, PID) ->
    lager:debug("Handle Info. PID: ~p. Info: ~p", [PID, Info]),
    
    case is_pid(PID) of
        true -> PID ! Info;
        false ->
            case whereis(PID) of
                undefined -> ok;
                Pid -> Pid ! Info
            end
    end,
    {noreply, PID}.

-spec terminate(any(), pid() | atom()) -> ok.
terminate(_Reason, _PID) ->
    ok.
