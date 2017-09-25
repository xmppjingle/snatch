-module(claws_xmpp_comp).
-behaviour(gen_statem).
-behaviour(claws).

-compile(export_all).

-include_lib("xmpp.hrl").
-include("snatch.hrl").

-record(data, {
    domain :: binary(),
    password :: binary(),
    host :: inet:socket_address(),
    port :: inet:port_number(),
    socket :: gen_tcp:socket(),
    stream
}).

-export([start_link/1]).
-export([init/1, callback_mode/0, terminate/3]).
-export([send/2, send/3]).

-define(INIT(D),
        <<"<?xml version='1.0' encoding='UTF-8'?>"
          "<stream:stream to='", D/binary, "' "
                         "xmlns='jabber:component:accept' "
                         "xmlns:stream='http://etherx.jabber.org/streams'>">>).
-define(AUTH(P), <<"<handshake>", P/binary, "</handshake>">>).

-define(SERVER, ?MODULE).

start_link(Params) ->
    gen_statem:start({local, ?MODULE}, ?MODULE, Params, []).

init(#{host := Host,
       port := Port,
       domain := Domain,
       password := Password}) ->
    {ok, disconnected, #data{host = Host,
                             port = Port,
                             domain = Domain,
                             password = Password}}.

callback_mode() -> handle_event_function.

%% API

connect() -> 
    gen_statem:cast(?SERVER, connect).

disconnect() ->
    gen_statem:stop(?SERVER).

%% States

disconnected(Type, connect, #data{host = Host, port = Port} = Data)
        when Type =:= cast orelse Type =:= state_timeout ->
    case gen_tcp:connect(Host, Port, [binary, {active, true}], 1000) of
        {ok, NewSocket} ->
            {next_state, connected, Data#data{socket = NewSocket},
             [{next_event, cast, init_stream}]};
        Error ->
            error_logger:error_msg("Connecting Error [~p:~p]: ~p~n",
                                   [Host, Port, Error]),
            {next_state, retrying, Data, [{next_event, cast, connect}]}
    end.


retrying(cast, connect, Data) ->
    {next_state, disconnected, Data, [{state_timeout, 3000, connect}]}.


connected(cast, init_stream, #data{} = Data) ->
    Stream = fxml_stream:new(whereis(?SERVER)),
    {next_state, stream_init, Data#data{stream = Stream},
     [{next_event, cast, init}]}.


stream_init(cast, init, #data{domain = Domain, socket = Socket} = Data) ->
    gen_tcp:send(Socket, ?INIT(Domain)),
    {keep_state, Data, []};

stream_init(cast, {received, {xmlstreamstart, _, Attribs}}, Data) ->
    case lists:keyfind(<<"id">>, 1, Attribs) of
        {<<"id">>, StreamID} ->
            {next_state, authenticate, Data,
             [{next_event, cast, {handshake, StreamID}}]};
        false ->
            error_logger:error_msg("stream invalid, no Stream ID", []),
            gen_tcp:close(Data#data.socket),
            {next_state, retrying, Data, [{next_event, cast, connect}]}
    end.


authenticate(cast, {handshake, StreamID},
             #data{socket = Socket, password = Secret} = Data) ->
    Concat = <<StreamID/binary, Secret/binary>>,
    <<Mac:160/integer>> = crypto:hash(sha, Concat),
    Password = iolist_to_binary(io_lib:format("~40.16.0b", [Mac])),
    gen_tcp:send(Socket, ?AUTH(Password)),
    {keep_state, Data, []};

authenticate(cast, {received, #xmlel{name = <<"handshake">>,
                                     children = []}}, Data) ->
    {next_state, ready, Data, []}.


ready(cast, {send, Packet}, #data{socket = Socket}) ->
    gen_tcp:send(Socket, Packet),
    {keep_state_and_data, []};

ready(cast, {received, #xmlel{attrs = Attribs} = Packet}, _Data) ->
    From = get_attr(<<"from">>, Attribs),
    To = get_attr(<<"to">>, Attribs),
    Via = #via{jid = From, exchange = To, claws = ?MODULE},
    snatch:received(Packet, Via),
    {keep_state_and_data, []}.


handle_event(info, {tcp, _Socket, Packet}, _State,
             #data{stream = Stream} = Data) ->
    NewStream = fxml_stream:parse(Stream, Packet),
    {keep_state, Data#data{stream = NewStream}, []};
handle_event(info, {TCP, _Socket}, _State, #data{stream = Stream} = Data)
        when TCP =:= tcp_closed orelse TCP =:= tcp_error ->
    snatch:disconnected(?MODULE),
    close_stream(Stream),
    {next_state, retrying, Data, [{next_event, cast, connect}]};
handle_event(info, {'$gen_event', {xmlstreamstart, _Name, _Attribs} = Packet},
             _State, Data) ->
    {keep_state, Data, [{next_event, cast, {received, Packet}}]};
handle_event(info, {'$gen_event', {xmlstreamend, _Name}}, _State,
             #data{stream = Stream} = Data) ->
    snatch:disconnected(?MODULE),
    close_stream(Stream),
    {next_state, retrying, Data, [{next_event, cast, connect}]};
handle_event(info, {'$gen_event', {xmlstreamerror, _Error}}, _State,
             #data{stream = Stream} = Data) ->
    snatch:disconnected(?MODULE),
    close_stream(Stream),
    {next_state, retrying, Data, [{next_event, cast, connect}]};
handle_event(info, {'$gen_event', {xmlstreamelement, Packet}}, _State,
             Data) ->
    {keep_state, Data,[{next_event, cast, {received, Packet}}]};
handle_event(Type, Content, State, Data) ->
    ?MODULE:State(Type, Content, Data).

terminate(_Reason, _StateName, _StateData) ->
    ok.

get_attr(ID, Attribs) ->
    get_attr(ID, Attribs, undefined).

get_attr(ID, Attribs, Default) ->
    case fxml:get_attr(ID, Attribs) of
        {value, Value} -> 
            Value;
        _ ->
            Default
    end.

send(Data, JID) ->
    send(Data, JID, undefined).

send(Data, _JID, _ID) ->
    gen_statem:cast(?MODULE, {send, Data}).

close_stream(Stream) ->
    catch fxml_stream:close(Stream).
