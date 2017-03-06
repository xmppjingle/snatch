-module(snatch).
-behaviour(gen_server).

-record(state, {jid = undefined, claws = undefined, listener = undefined}).

-export([start_link/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([forward/2]).

start_link(JID, Claws, Listener) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [JID, Claws, Listener], []).

init([JID, Claws, Listener]) ->
	{ok, #state{jid = JID, claws = Claws, listener = Listener}}.

handle_call({send, _Data} = Request, _From, #state{claws = Claws} = S) ->
    Result = forward(Claws, Request),
    {reply, Result, S}.

handle_cast({received, _Data} = M, #state{listener = Listener} = S) ->
    forward(Listener, M),
    {noreply, S};

handle_cast(_Cast, S) ->
    io:format("Cast: ~p  ~n", [_Cast]),
    {noreply, S}.

handle_info(_Info, S) ->
    io:format("Info: ~p  ~n", [_Info]),
    {noreply, S}.

terminate(_, _) ->
    io:format("Terminating...~n", []),
    ok.

forward(Listener, Data) when is_pid(Listener) ->
    io:format("Forward: ~p  -> ~p ~n", [Listener, Data]),
    Listener ! Data;
forward(Listener, Data) when is_atom(Listener) ->
    io:format("Forward: ~p  -> ~p ~n", [Listener, Data]),
    gen_server:cast(Listener, Data).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
