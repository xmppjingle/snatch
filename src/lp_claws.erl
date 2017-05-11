-module(lp_claws).
-behaviour(gen_server).
-behaviour(claws).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([send/2]).

-include_lib("xmpp.hrl").

-record(state, {url, channel, listener, params, pid}).

start_link(Params) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).

init(#{url := URL, listener := Listener}) ->
	State = #state{url = URL, listener = Listener},
	gen_server:cast(?MODULE, connect),
	{ok, State}.

create_bind_url(#state{url = URL} = S) ->
	case httpc:request(get, {URL, []}, [], [{sync, false}, {stream, {self, once}}]) of
		{ok, Channel} ->
			S#state{channel = Channel, params = undefined};
		_ -> 
			S#state{channel = undefined, params = undefined}
	end.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(connect, #state{url = URL} = State) ->	
	lager:debug("Connection Requested to: ~p~n", [URL]),
    {noreply, create_bind_url(State)};
handle_cast(_Msg, State) ->	
	lager:debug("Unknown Cast[~p]: ~p~n", [State, _Msg]),
    {noreply, State}.

handle_info({http, {_Pid, stream_start, Params}}, #state{listener = Listener} = State) ->
	lager:debug("Channel Established: ~p~n", [Params]),
	snatch:forward(Listener, {connected, ?MODULE}),
	{noreply, State#state{params = Params}};
handle_info({http, {_Pid, stream_start, Params, Pid}}, #state{listener = Listener} = State) ->
	lager:debug("Channel Established: ~p~n", [Params]),
	snatch:forward(Listener, {connected, ?MODULE}),
	{noreply, State#state{params = Params, pid = Pid}};
handle_info({http, {_Pid, stream_end, Params}}, #state{listener = Listener} = State) ->
	lager:debug("Channel Disconnected: ~p~n", [Params]),
	snatch:forward(Listener, {disconnected, ?MODULE}),
	{noreply, State#state{params = Params, channel = undefined}};
handle_info({http, {_Pid, stream, Data}}, #state{listener = Listener, pid = Pid} = State) ->
	lager:debug("Channel Received: ~p~n", [Data]),
	snatch:forward(Listener, {received, Data}),
	httpc:stream_next(Pid),
	{noreply, State};
handle_info(_Info, State) ->
	lager:debug("Info: ~p~n", [_Info]),
    {noreply, State}.

terminate(_Reason, #state{channel = Channel}) when Channel /= undefined ->
	httpc:cancel_request(Channel),
	lager:debug("Terminated: ~p~n", [Channel]),
    ok;
terminate(_Reason, _State) ->
	lager:debug("Terminated at: ~p~n", [_State]),
	ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

send(Data, JID) ->
	gen_server:cast(?MODULE, {send, Data, JID}).
