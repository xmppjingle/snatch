-module(snatch).
-behaviour(gen_server).

-include("snatch.hrl").

-record(state, {jid = undefined, claws = undefined, listener = undefined}).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([forward/2, is_full/1, to_bare/1, send/2, send/1]).

-include_lib("xmpp.hrl").

-define(INIT_PARAMS, [JID, Claws, Listener]).

start_link(?INIT_PARAMS) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, ?INIT_PARAMS, []).

init(?INIT_PARAMS) ->
    mnesia:start(),
    mnesia:create_table(route,  [{attributes, record_info(fields, route)}]),
	{ok, #state{jid = JID, claws = Claws, listener = Listener}}.

handle_call(_Call, _From, S) ->
    lager:debug("Unknown Call: ~p ~n", [_Call]),
    {reply, ok, S}.

handle_cast({send, Data}, #state{claws = Claws} = S) ->
    Claws:send(Data, <<"unknown">>),
    {noreply, S};

handle_cast({send, Data, JID}, #state{claws = Claws} = S) ->
    (get_route(JID, Claws)):send(Data, JID),
    {noreply, S};

handle_cast({received, _Data, #route{} = R} = M, #state{listener = Listener} = S) ->
    add_route(R),
    forward(Listener, M),
    {noreply, S};

handle_cast({received, _Data} = M, #state{listener = Listener} = S) ->
    forward(Listener, M),
    {noreply, S};

handle_cast(_Cast, S) ->
    lager:debug("Cast: ~p  ~n", [_Cast]),
    {noreply, S}.

handle_info(_Info, S) ->
    lager:debug("Info: ~p  ~n", [_Info]),
    {noreply, S}.

terminate(_, _) ->
    lager:debug("Terminating...~n", []),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

add_route(undefined) -> ok;
add_route(#route{jid = JID, claws = Claws}) when JID /= undefined, Claws /= undefined ->
    mnesia:dirty_write(#route{jid = JID, claws = Claws}),
    lager:debug("Added Route[~p]: ~p ~n", [JID, Claws]);
add_route(_) -> ok.

get_route(JID, Default) ->
    case mnesia:dirty_read(route, JID) of
        [#route{claws = Claws}|_] ->
            Claws;
        _ ->
            Default
    end.

forward(Listener, Data) when is_pid(Listener) ->
    lager:debug("Forward: ~p  -> ~p ~n", [Listener, Data]),
    Listener ! Data;
forward(Listener, Data) when is_atom(Listener) ->
    lager:debug("Forward: ~p  -> ~p ~n", [Listener, Data]),
    gen_server:cast(Listener, Data).

send(Data, JID) ->
    gen_server:cast(?MODULE, {send, Data, JID}).

send(Data) ->
    gen_server:cast(?MODULE, {send, Data}).

to_bare(#jid{user = User, server = Domain}) ->
    <<User/binary, "@", Domain/binary>>;
to_bare(JID) when is_binary(JID) ->
    to_bare(jid:decode(JID)).

is_full(#jid{resource = <<>>}) -> false;
is_full(JID) when is_binary(JID) -> 
    is_full(jid:decode(JID));
is_full(#jid{}) -> true;
is_full(_) -> false.