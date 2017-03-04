-module(snatch).
-behaviour(gen_server).

-record(state, {user, domain, password, claws = undefined, stream=undefined, state=undefined, listener = undefined}).

-define(INIT(D), <<"<?xml version='1.0' encoding='UTF-8'?><stream:stream to='", D/binary, "' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams' version='1.0'>">>).
-define(AUTH(U, P), <<"<iq type='set' id='auth2'><query xmlns='jabber:iq:auth'><username>", U/binary, "</username><password>", P/binary, "</password><resource>snatch</resource></query></iq>">>).

-export([start_link/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-export([forward/2, send/1]).

start_link(User, Domain, Password, Listener) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [User, Domain, Password, Listener], []).

init([User, Domain, Password, Listener]) ->
	{ok, #state{user=User, domain=Domain, password=Password, listener = Listener}}.

handle_call({send, _Data} = Request, _From, #state{state = binded, claws = Claws} = S) ->
    Result = forward(Claws, Request),
    {reply, Result, S}.

handle_cast({connected, Claws}, #state{domain = Domain} = S) ->
    io:format("Connected: ~p ~n", [Claws]),    
    Stream = fxml_stream:new(whereis(?MODULE)),
    send(Claws, ?INIT(Domain)),
    {noreply, S#state{claws = Claws, state = connected, stream = Stream}};

handle_cast({received, Data}, #state{user = User, password = Password, state = connected, claws = Claws, stream = Stream} = S) ->
    NewStream = fxml_stream:parse(Stream, Data),
    send(Claws, ?AUTH(User, Password)),
    {noreply, S#state{claws = Claws, state = auth, stream = NewStream}};

handle_cast({received, Data}, #state{state = auth, listener = Listener, stream = Stream} = S) ->
    NewStream = fxml_stream:parse(Stream, Data),
    forward(Listener, {binded, ?MODULE}),
    {noreply, S#state{state = binded, stream = NewStream}};

handle_cast({received, Data}, #state{state = binded, stream = Stream} = S) ->
    NewStream = fxml_stream:parse(Stream, Data),
    {noreply, S#state{stream = NewStream}};

handle_cast({closed}, #state{listener = Listener} = S) ->
    forward(Listener, {closed, socket}),
    {noreply, S#state{stream = undefined, state = undefined}};

handle_cast(_Cast, S) ->
    io:format("Cast: ~p  ~n", [_Cast]),
    {noreply, S}.

handle_info({'$gen_event', {xmlstreamelement, Packet}}, #state{listener = Listener, state = binded} = S) ->
    forward(Listener, {received, Packet}),
    {noreply, S};

handle_info({'$gen_event', {xmlstreamend, Packet}}, #state{listener = Listener, claws = Claws, stream = Stream} = S) ->
    fxml_stream:close(Stream),
    forward(Claws, {close}),
    forward(Listener, {closed, Packet}),
    {noreply, S};

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

send(Data) ->
    send(?MODULE, Data).

send(To, Data) ->
    gen_server:call(To, {send, Data}).