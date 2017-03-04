-module(tcp_claws).
-behaviour(gen_server).
-compile(export_all).

-record(state, {host, port, socket=undefined, state=undefined, listener}).

-export([start_link/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link(Host, Port, Listener) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Host, Port, Listener], []).

init([Host, Port, Listener]) ->
	connect(Host, Port, Listener).

connect(Host, Port, Listener) ->
	io:format("Connecting...~n", []),
	case gen_tcp:connect(Host, Port, [binary, {active, true}]) of
		{ok, NewSocket} ->
			timer:apply_after(1000, snatch, forward, [Listener, {connected, ?MODULE}]),
			io:format("Connected.~n", []),
			{ok, #state{socket=NewSocket, state = connected, listener = Listener, host = Host, port = Port}};
		_Error -> 
			io:format("Connecting Error [~p:~p]: ~p~n", [Host, Port, _Error]),
			timer:sleep(3000),
			connect(Host, Port, Listener)
	end.

close(Socket, #state{host = Host, port = Port, listener = Listener, state = State}) when State /= undefined ->
	io:format("Restarting...~n", []),
	gen_tcp:close(Socket),
	connect(Host, Port, Listener);

close(_, S) -> {ok, S}.

handle_call({send, Data}, _From, #state{state = connected, socket = Socket} = S) ->
    Result = gen_tcp:send(Socket, Data),
    {reply, Result, S}.

handle_cast({close}, #state{socket = Socket} = S) ->
	{ok, State} = close(Socket, S),
	{noreply, State};

handle_cast(_Cast, S) ->
    {noreply, S}.

handle_info({tcp, _Socket, Data}, #state{listener = Listener} = S) ->
	io:format("Received: ~p ~n", [Data]),
	gen_server:cast(Listener, {received, Data}),
	{noreply, S};

handle_info({Event, Socket}, #state{listener = Listener, state = State} = S) when State /= undefined, Event == tcp_close; Event == tcp_error ->
	gen_server:cast(Listener, {closed}),
	{ok, NewState} = close(Socket, S),
	{noreply, NewState};

handle_info(_Info, S) ->
    {noreply, S}.

terminate(_, _) ->
	io:format("Terminating...~n", []),
	ok.