-module(xmpp_claws).
-behaviour(gen_statem).
-compile(export_all).

-record(data, {user, domain, password, resource, host, port, socket=undefined, listener, stream}).

-export([start_link/1]).
-export([terminate/3,code_change/4,init/1,callback_mode/0]).

-define(INIT(D), <<"<?xml version='1.0' encoding='UTF-8'?><stream:stream to='", D/binary, "' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams' version='1.0'>">>).
-define(AUTH(U, P, R), <<"<iq type='set' id='auth2'><query xmlns='jabber:iq:auth'><username>", U/binary, "</username><password>", P/binary, "</password><resource>", R/binary, "</resource></query></iq>">>).
-define(AUTH_SASL(B64), << "<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='PLAIN'>", B64/binary, "</auth>">>).
-define(BIND(R), <<"<iq type='set' id='bind3' xmlns='jabber:client'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><resource>", R/binary, "</resource></bind></iq>">>).
-define(SESSION, <<"<iq type='set' id='session4'><session xmlns='urn:ietf:params:xml:ns:xmpp-session'/></iq>">>).
-define(PRESENCE, <<"<presence/>">>).

-define(INIT_PARAMS, [Host, Port, User, Domain, Password, Resource, Listener]).

name() -> xmpp_claws.

start_link(?INIT_PARAMS) ->
    gen_statem:start({local, name()}, ?MODULE, ?INIT_PARAMS, []).

init(?INIT_PARAMS) ->
	{ok, disconnected, #data{host = Host, port = Port, user = User, domain = Domain, password = Password, resource = Resource, listener = Listener}}.

callback_mode() -> handle_event_function.

terminate(_E, _F, _G) ->
	lager:debug("Terminating...~n~p~n~p~n~p~n", [_E, _F, _G]), void.

code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.

%% API

connect() -> 
	gen_statem:cast(name(), connect).

disconnect() ->
	gen_statem:cast(name(), disconnect).

%% States

disconnected(Type, connect, #data{host = Host, port = Port} = Data) when Type == cast; Type == state_timeout ->
	lager:info("Connecting...~n", []),
	case gen_tcp:connect(Host, Port, [binary, {active, true}]) of
		{ok, NewSocket} ->
			lager:info("Connected.~n", []),
			{next_state, connected, Data#data{socket = NewSocket}, [{next_event, cast, init_stream}]};
		_Error -> 
			lager:warn("Connecting Error [~p:~p]: ~p~n", [Host, Port, _Error]),
			{next_state, retrying, Data, [{next_event, cast, connect}]}
	end;

disconnected(cast, disconnect, _Data) ->
	{keep_state_and_data, []}.

retrying(cast, connect, Data) ->
	{next_state, disconnected, Data, [{state_timeout, 3000, connect}]}.

connected(cast, init_stream, #data{} = Data) ->
	Stream = fxml_stream:new(whereis(name())),
	{next_state, stream_init, Data#data{stream = Stream}, [{next_event, cast, init}]}.

stream_init(cast, init, #data{domain = Domain, socket = Socket} = Data) ->
	gen_tcp:send(Socket, ?INIT(Domain)),
	{keep_state, Data, []};

stream_init(cast, {received, _Packet}, Data) ->	
	{next_state, authenticate, Data, [{next_event, cast, auth_sasl}]}.

authenticate(cast, auth, #data{user = User, password = Password, resource = Resource, socket = Socket} = Data) ->
	gen_tcp:send(Socket, ?AUTH(User, Password, Resource)),
	{keep_state, Data, []};

authenticate(cast, auth_sasl, #data{user = User, password = Password, socket = Socket} = Data) ->
	B64 = base64:encode(<<"\0", User/binary, "\0", Password/binary>>),
	gen_tcp:send(Socket, ?AUTH_SASL(B64)),
	{keep_state, Data, []};

authenticate(cast, {received, _Packet}, Data) ->
	{next_state, bind, Data, [{next_event, cast, bind}]}.

bind(cast, bind, #data{resource = Resource, socket = Socket, domain = Domain, stream = Stream} = Data) ->
	case Stream of <<>> -> ok; _ -> fxml_stream:close(Stream) end,
	NewStream = fxml_stream:new(whereis(name())),
	gen_tcp:send(Socket, ?INIT(Domain)),
	gen_tcp:send(Socket, ?BIND(Resource)),
	{keep_state, Data#data{stream = NewStream}, []};

bind(cast, {received, _Packet}, #data{socket = Socket} = Data) ->
	gen_tcp:send(Socket, ?SESSION),	
	gen_tcp:send(Socket, ?PRESENCE),
	{next_state, binding, Data, []}.

binding(cast, {received, _Packet}, Data) ->
	{next_state, binded, Data, []}.

binded(cast, {send, Packet}, #data{socket = Socket}) ->
	gen_tcp:send(Socket, Packet),
	{keep_state_and_data, []};

binded(cast, {received, Packet} = R, #data{listener = Listener}) ->
	lager:debug("Received Packet: ~p ~n", [Packet]),
	snatch:forward(Listener, R),
	{keep_state_and_data, []}.

handle_event(info, {tcp, _Socket, Packet}, _State, #data{stream = Stream} = Data) ->
	lager:debug("TCP Received: ~p ~n", [Packet]),
	NewStream = fxml_stream:parse(Stream, Packet),
    {keep_state, Data#data{stream = NewStream}, []};
handle_event(info, {TCP, _Socket}, _State, #data{stream = Stream} = Data) when TCP == tcp_closed; TCP == tcp_error ->
	case Stream of <<>> -> ok; _ -> fxml_stream:close(Stream) end,
    {next_state, retrying, Data, [{next_event, cast, connect}]};
handle_event(info, {'$gen_event', {xmlstreamstart, _Name, _Attribs}}, _State, _Data) ->
    {keep_state_and_data, []};
handle_event(info, {'$gen_event', {xmlstreamend, _Name}}, _State, #data{stream = Stream} = Data) ->
	lager:info("Stream End: ~p ~n", [_Name]),
	case Stream of <<>> -> ok; _ -> fxml_stream:close(Stream) end,
    {next_state, retrying, Data, [{next_event, cast, connect}]};
handle_event(info, {'$gen_event', {xmlstreamerror, Error}}, _State, #data{stream = Stream} = Data) ->
	lager:warn("Stream Error: ~p ~n", [Error]),
	case Stream of <<>> -> ok; _ -> fxml_stream:close(Stream) end,
    {next_state, retrying, Data, [{next_event, cast, connect}]};
handle_event(info, {'$gen_event', {xmlstreamelement, Packet}}, _State, Data) ->
    {keep_state, Data,[{next_event, cast, {received, Packet}}]};
handle_event(Type, Content, State, Data) ->
	lager:debug("Anonymous: ~p ~p~n", [Type, Content]),
	?MODULE:State(Type, Content, Data).