-module(tcp_claws).
-behaviour(gen_server).
-compile(export_all).

-record(state, {host, port, socket=undefined, state=undefined, listener}).

-export([start_link/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link(Host, Port, Listener) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Host, Port, Listener], []).

init([Host, Port, Listener]) ->
	connect(Host, Port, Listener).

connect(Host, Port, Listener) ->
	case gen_tcp:connect(Host, Port, [binary, {active, true}]) of
		{ok, NewSocket} ->
			timer:apply_after(1000, snatch, forward, [Listener, {connected, ?MODULE}]),
			{ok, #state{socket=NewSocket, state = connected, listener = Listener}};
		_ -> 
			timer:sleep(3000),
			connect(Host, Port, Listener)
	end.

handle_call({send, Data}, _From, #state{state = connected, socket = Socket} = S) ->
    Result = gen_tcp:send(Socket, Data),
    {reply, Result, S}.

handle_cast(_Cast, S) ->
    {noreply, S}.

handle_info({tcp, _Socket, Data}, #state{listener = Listener} = S) ->
	io:format("Received: ~p ~n", [Data]),
	gen_server:cast(Listener, {received, Data}),
	{noreply, S};

handle_info({tcp_closed, _Socket}, #state{listener = Listener} = S) ->
	gen_server:cast(Listener, {closed}),
	{noreply, S};

handle_info({tcp_error, _Socket}, #state{listener = Listener} = S) ->
	gen_server:cast(Listener, {closed}),
	{noreply, S};

handle_info(_Info, S) ->
    {noreply, S}.
