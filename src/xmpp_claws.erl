-module(xmpp_claws).
-behaviour(gen_server).
-compile(export_all).

-record(state, {user, domain, password, host, port, socket=undefined, state=undefined, listener, stream}).

-export([start_link/6]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(INIT(D), <<"<?xml version='1.0' encoding='UTF-8'?><stream:stream to='", D/binary, "' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams' version='1.0'>">>).
-define(AUTH(U, P), <<"<iq type='set' id='auth2'><query xmlns='jabber:iq:auth'><username>", U/binary, "</username><password>", P/binary, "</password><resource>snatch</resource></query></iq>">>).

-define(INIT_PARAMS, [Host, Port, User, Domain, Password, Listener]).

start_link(Host, Port, User, Domain, Password, Listener) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, ?INIT_PARAMS, []).

init(?INIT_PARAMS) ->
	connect(#state{host = Host, port = Port, user = User, domain = Domain, password = Password, listener = Listener}).

connect(#state{host = Host, port = Port} = S) ->
	io:format("Connecting...~n", []),
	case gen_tcp:connect(Host, Port, [binary, {active, true}]) of
		{ok, NewSocket} ->
			?MODULE ! {connected, ?MODULE},
			io:format("Connected.~n", []),
			{ok, S#state{socket=NewSocket, state = connected}};
		_Error -> 
			io:format("Connecting Error [~p:~p]: ~p~n", [Host, Port, _Error]),
			timer:sleep(3000),
			connect(S)
	end.

close(Socket, Reason, #state{listener = Listener, state = State} = S) when State /= undefined ->
	io:format("Restarting...~n", []),
	gen_tcp:close(Socket),
	snatch:forward(Listener, {closed, Reason}),
	connect(S);

close(_, _, S) -> {ok, S}.

handle_call(_, _, S) ->
    {reply, ok, S}.	

handle_cast({received, Data}, #state{state = connected, user = User, password = Password, stream = Stream} = S) ->
    NewStream = fxml_stream:parse(Stream, Data),
    gen_server:cast(?MODULE, {send, ?AUTH(User, Password)}),
    {noreply, S#state{state = auth, stream = NewStream}};
	
handle_cast({received, Data}, #state{state = auth, listener = Listener, stream = Stream} = S) ->
    NewStream = fxml_stream:parse(Stream, Data),
    snatch:forward(Listener, {binded}),
    {noreply, S#state{state = binded, stream = NewStream}};

handle_cast({received, Data}, #state{state = binded, stream = Stream, listener = Listener} = S) ->
    NewStream = fxml_stream:parse(Stream, Data),
    snatch:forward(Listener, {received, Data}),
    {noreply, S#state{stream = NewStream}};

handle_cast({send, Data}, #state{state = _State, socket = Socket} = S) ->
	io:format("Sending TCP: ~p~n", [Data]),
    gen_tcp:send(Socket, Data),
    {noreply, S};

handle_cast(_Cast, S) ->
    {noreply, S}.

handle_info({tcp, _Socket, Data}, #state{} = S) ->
	io:format("Received TCP: ~p ~n", [Data]),
	gen_server:cast(?MODULE, {received, Data}),
	{noreply, S};

handle_info({connected, _PID}, #state{domain = Domain} = S) ->
    io:format("Connected: ~p ~n", [_PID]),    
    Stream = fxml_stream:new(whereis(?MODULE)),
    gen_server:cast(?MODULE, {send, ?INIT(Domain)}),
    {noreply, S#state{state = connected, stream = Stream}};

handle_info({close, Reason}, #state{socket = Socket} = S) ->
	{ok, State} = close(Socket, Reason, S),
	{noreply, State};

handle_info({'$gen_event', {xmlstreamelement, Packet}}, #state{listener = Listener, state = binded} = S) ->
    snatch:forward(Listener, {received, Packet}),
    {noreply, S};

handle_info({'$gen_event', {xmlstreamend, _Packet}}, #state{stream = Stream} = S) ->
    fxml_stream:close(Stream),
    ?MODULE ! {close, stream},
    {noreply, S};

handle_info({Event, _Socket}, #state{state = State} = S) when State /= undefined, Event == tcp_close; Event == tcp_error ->
    ?MODULE ! {close, socket},
	{noreply, S#state{state = undefined}};

handle_info(_Info, S) ->
    {noreply, S}.

terminate(_, _) ->
	io:format("Terminating...~n", []),
	ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
