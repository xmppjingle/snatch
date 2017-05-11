-module(lp_claws).
-behaviour(gen_server).
-behaviour(claws).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([send/2]).

-export([read_chunk/3]).

-include_lib("xmpp.hrl").

-record(state, {url, channel, listener, params, pid, stream = <<>>, buffer = <<>>, size = -1}).

-define(H, <<"\r\n">>).

name() -> lp_claws.

start_link(Params) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).

init(#{url := URL, listener := Listener}) ->
	State = #state{url = URL, listener = Listener},
	gen_server:cast(?MODULE, connect),
	{ok, State}.

create_bind_url(#state{url = URL} = S) ->
	case httpc:request(get, {URL, []}, [], [{sync, false}, {stream, self}]) of
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
	{noreply, State#state{params = Params, stream = fxml_stream:new(whereis(name())), pid = Pid}};
handle_info({http, {_Pid, stream_end, Params}}, #state{listener = Listener} = State) ->
	lager:debug("Channel Disconnected: ~p~n", [Params]),
	snatch:forward(Listener, {disconnected, ?MODULE}),
	{noreply, State#state{params = Params, channel = undefined}};
handle_info({http, {_Pid, stream, Data}}, #state{stream = S, buffer = Buffer, size = Size} = State) ->
	lager:debug("Channel Received: ~p~n", [Data]),
	Stream = check_stream(S),
	NState = case read_chunk(Size, Buffer, Data) of
		{wait, NSize, NBuffer} ->
			State#state{buffer = NBuffer, size = NSize};
		{chunk, _S, Packet, Rem} ->
			fxml_stream:parse(Stream, Packet),
			State#state{buffer = Rem, size = -1}
		end,
	{noreply, NState};

handle_info({'$gen_event', {xmlstreamstart, _Name, _Attribs}}, State) ->
    {noreply, State};
handle_info({'$gen_event', {xmlstreamend, _Name}}, #state{stream = Stream} = State) ->
	lager:info("Stream End: ~p ~n", [_Name]),
	close(Stream),
    {noreply, State#state{stream = <<>>}};
handle_info({'$gen_event', {xmlstreamerror, Error}}, #state{stream = Stream} = State) ->
	lager:error("Stream Error: ~p ~n", [Error]),
	close(Stream),
    {noreply, State#state{stream = <<>>}};
handle_info({'$gen_event', {xmlstreamelement, Data}}, #state{listener = Listener} = State) ->
	snatch:forward(Listener, {received, Data}),
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

close(<<>>) -> ok;
close(Stream) -> fxml_stream:close(Stream).

check_stream(<<>>) -> 
	fxml_stream:new(whereis(name()));
check_stream(S) -> S.

read_chunk(-1, Buffer, Data) ->
	Bin = <<Buffer/binary, Data/binary>>,
	{I, J} = binary:match(Bin, ?H),
    Size = erlang:binary_to_integer(binary:part(Data, {0, I + J - byte_size(?H)}), 16),
    Offset = I + J,
    read_chunk(Size, binary:part(Bin, {Offset, byte_size(Bin) - Offset}), <<>>);
read_chunk(Size, Buffer, Data) when byte_size(Buffer) + byte_size(Data) >= Size ->
	Bin = <<Buffer/binary, Data/binary>>,
	{chunk, Size, binary:part(Bin, {0, Size}), binary:part(Bin, {Size, byte_size(Bin) - Size})};
read_chunk(Size, Buffer, Data) ->
	{wait, Size, <<Buffer/binary, Data/binary>>}.
