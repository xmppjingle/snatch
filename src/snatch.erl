-module(snatch).
-behaviour(gen_server).

-record(state, {jid = undefined, claws = undefined, listener = undefined}).

-export([start_link/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([forward/2, is_full/1, to_bare/1]).

-include_lib("xmpp.hrl").

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

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

forward(Listener, Data) when is_pid(Listener) ->
    lager:debug("Forward: ~p  -> ~p ~n", [Listener, Data]),
    Listener ! Data;
forward(Listener, Data) when is_atom(Listener) ->
    lager:debug("Forward: ~p  -> ~p ~n", [Listener, Data]),
    gen_server:cast(Listener, Data).

to_bare(#jid{user = User, server = Domain}) ->
    <<User/binary, "@", Domain/binary>>;
to_bare(JID) when is_binary(JID) ->
    to_bare(jid:decode(JID)).

is_full(#jid{resource = <<>>}) -> false;
is_full(JID) when is_binary(JID) -> 
    is_full(jid:decode(JID));
is_full(#jid{}) -> true;
is_full(_) -> false.