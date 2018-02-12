-module(claws_fcm_worker).
-behaviour(gen_statem).
-behaviour(claws).

-include_lib("fast_xml/include/fxml.hrl").
-include("snatch.hrl").

-record(data, {
    gcs_add :: inet:socket_address(),
    gcs_port :: inet:port_number(),
    server_id,
    server_key,
    socket :: gen_tcp:socket(),
    stream
}).

-export([start_link/1, connect/0, disconnect/0]).
-export([init/1,
         callback_mode/0,
         handle_event/4,
         code_change/4,
         terminate/3]).
-export([disconnected/3,
         retrying/3,
         connected/3,
         stream_init/3,
        wait_for_features/3,
         authenticate/3,
         bind/3,
    wait_for_binding/3,
    wait_for_result/3,
         binding/3,
         binded/3,
          drainned/3]).


-define(INIT,
  %% Right now it seems the domain is gcm.googleapis.com whenever we use gcm or fcm. This might change as google finish upgrade to fcm
  <<"<stream:stream to='gcm.googleapis.com' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>">>).


-define(AUTH_SASL(B64), << "<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' "
                                 "mechanism='PLAIN'>", B64/binary, "</auth>">>).

-define(BIND, <<"<iq type='set'>"
                   "<bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'>"
                   "</bind></iq>">>).


-define(SERVER, ?MODULE).

start_link(FCMParams) ->
    io:format("~nstartlink push claw",[]),
    ssl:start(),
    gen_statem:start_link(?MODULE, [FCMParams], []).

init([#{gcs_add := Gcs_add, gcs_port := Gcs_Port, server_id := ServerId, server_key := ServerKey}]) ->
    io:format("~nStarting claw :~p", [#{gcs_add => Gcs_add, gcs_port => Gcs_Port, server_id => ServerId, server_key => ServerKey}]),
    {ok, disconnected, #data{gcs_add = Gcs_add, gcs_port = Gcs_Port, server_id = ServerId, server_key = ServerKey}, [{next_event, cast, connect}]}.

callback_mode() -> handle_event_function.

%% API

connect() ->
    gen_statem:cast(?SERVER, connect).

disconnect() ->
    gen_statem:cast(?SERVER, disconnect).

%% States

disconnected(Type, connect, #data{gcs_add  = Host, gcs_port = Port} = Data)
        when Type =:= cast orelse Type =:= state_timeout ->
    case ssl:connect(Host, Port, [binary, {active, true}]) of
        {ok, NewSocket} ->
            {next_state, connected, Data#data{socket = NewSocket},
             [{next_event, cast, init_stream}]};
        Error ->
            error_logger:error_msg("Connecting Error [~p:~p]: ~p~n",
                                   [Host, Port, Error]),
            {next_state, retrying, Data, [{next_event, cast, connect}]}
    end;

disconnected(cast, disconnect, _Data) ->
    {keep_state_and_data, []}.

retrying(cast, connect, Data) ->
    {next_state, disconnected, Data, [{state_timeout, 3000, connect}]}.

connected(cast, init_stream, #data{} = Data) ->
    Stream = fxml_stream:new(self()),
    {next_state, stream_init, Data#data{stream = Stream},
     [{next_event, cast, init}]}.

stream_init(cast, init, #data{socket = Socket} = Data) ->
    io:format("~n--> sending ~p",[?INIT]),
    ssl:send(Socket, ?INIT),
    {keep_state, Data, []};

stream_init(info, {ssl, _SSLSocket, _Message}, Data) ->
    io:format("~nSteam init Reeceived :~p",[_Message]),
    {next_state, wait_for_features, Data, []}.


wait_for_features(info, {ssl, _SSLSocket, _Message}, Data) ->
  io:format("~nwait_for_features Reeceived :~p",[_Message]),
  {next_state, authenticate, Data, [{next_event, cast, auth_sasl}]}.


authenticate(cast, auth_sasl, #data{server_id = User, server_key = Password,
                                    socket = Socket} = Data) ->
    B64 = base64:encode(<<0, User/binary, 0, Password/binary>>),
  io:format("~n--> Authenticate sending ~p",[?AUTH_SASL(B64)]),

  ssl:send(Socket, ?AUTH_SASL(B64)),
    {keep_state, Data, []};

authenticate(info, {ssl, _SSLSocket, _Message}, Data) ->
  io:format("~nAuthenticate Reeceived :~p",[_Message]),
  {next_state, bind, Data, [{next_event, cast, bind}]}.

bind(cast, bind, #data{socket = Socket, gcs_add = _Gcs_add,
                       stream = Stream} = Data) ->
    close_stream(Stream),
    NewStream = fxml_stream:new(self()),
    io:format("~n--> bind sending ~p",[?INIT]),
    ssl:send(Socket, ?INIT),
    {keep_state, Data#data{stream = NewStream}, []};

bind(info, {ssl, _SSLSock, _Message}, Data) ->
  io:format("~nbind Reeceived :~p",[_Message]),

 %% io:format("~n-->sending ~p",[?BIND]),
  {next_state, wait_for_binding, Data, []}.



wait_for_binding(info, {ssl, _SSLSock, _Message}, #data{socket = Socket} = Data) ->
  io:format("~nwait_for_binding Reeceived :~p",[_Message]),
  io:format("~n--> wait_for_binding sending ~p",[?BIND]),
  ssl:send(Socket, ?BIND),
  {next_state, wait_for_result, Data, []}.



wait_for_result(info, {ssl, _SSLSock, _Message},  Data) ->
  io:format("~nwait_for_result Reeceived :~p",[_Message]),
  {next_state, binded, Data, []}.



binding(info, {ssl, _SSLSock, _Message}, Data) ->
  io:format("~nbinding Reeceived :~p",[_Message]),
  io:format("~nClaw is connected",[]),
  snatch:connected(claws_fcm),
    {next_state, binded, Data, []}.

binded(cast, {send, To, Payload}, #data{socket = Socket}) ->
    io:format("~nReceived payload :~p",[Payload]),

    JSONPayload = lists:foldl(
      fun({Key,Value},Acc) -> maps:put(Key, Value,Acc) end,#{<<"message_id">> => base64:encode(crypto:strong_rand_bytes(6)), <<"to">> => To},Payload),

    FinalPayload = {xmlcdata, jsone:encode(JSONPayload)},

    io:format("~nSending payload :~p",[FinalPayload]),
    Gcm = {xmlel, <<"gcm">>, [{<<"xmlns">>, <<"google:mobile:data">>}], [FinalPayload]},
    Mes = {xmlel, <<"message">>, [{<<"id">>, base64:encode(crypto:strong_rand_bytes(6))}], [Gcm]},
    io:format("~nSending push :~p",[Mes]),
    ssl:send(Socket, fxml:element_to_binary(Mes)),
    {keep_state_and_data, []};

binded(cast, {received, #xmlel{} = Packet}, _Data) ->
    io:format("~npuscomp received ~p",[Packet]),
    From = snatch_xml:get_attr(<<"from">>, Packet),
    To = snatch_xml:get_attr(<<"to">>, Packet),
    Via = #via{jid = From, exchange = To, claws = ?MODULE},
    snatch:received(Packet, Via),
    {keep_state_and_data, []};

binded(info, {ssl, _SSLSock, <<" ">>}, _Data) ->
  io:format("~nKEEP ALIVE", []),
  {keep_state_and_data, []};


binded(info, {ssl, _SSLSock, Message}, Data) ->
  DecPak = fxml_stream:parse_element(Message),
  io:format("~npuscomp received SSL ~p on socket ~p",[DecPak, _SSLSock]),
  case DecPak#xmlel.name of
    <<"message">> ->
      case process_fcm_message(DecPak, Data) of
        ok ->
          {keep_state_and_data, []};
        {next_state, State} ->
          {next_state, State, Data, []};
        _ ->
          {keep_state_and_data, []}
      end;
    _ ->
      snatch:received(DecPak),
      {keep_state_and_data, []}
  end;


binded(info, {ssl, _SSLSock, Message}, _Data) ->
  io:format("~npuscomp received SSL ~p",[Message]),
  snatch:received(Message),
  {keep_state_and_data, []};

binded(cast, _Unknown, _Data) ->
    {keep_state_and_data, []}.


drainned(_, {ssl, _SSLSock, Message}, Data) ->
  io:format("~nFCM claw received ~p in state drainned",[Message]),
  {stop, normal, Data}.


handle_event(info, {tcp, _Socket, Packet}, _State,
             #data{stream = Stream} = Data) ->
    NewStream = fxml_stream:parse(Stream, Packet),
    {keep_state, Data#data{stream = NewStream}, []};
handle_event(info, {TCP, _Socket}, _State, #data{stream = Stream} = Data)
        when TCP =:= tcp_closed orelse TCP =:= tcp_error ->
    snatch:disconnected(?MODULE),
    close_stream(Stream),
    {next_state, retrying, Data, [{next_event, cast, connect}]};
handle_event(info, {'$gen_event', {xmlstreamstart, _Name, _Attribs}}, _State, _Data) ->
    {keep_state_and_data, []};
handle_event(info, {'$gen_event', {xmlstreamend, _Name}}, _State, #data{stream = Stream} = Data) ->
    snatch:disconnected(?MODULE),
    close_stream(Stream),
    {next_state, retrying, Data, [{next_event, cast, connect}]};
handle_event(info, {'$gen_event', {xmlstreamerror, Error}}, _State, #data{stream = Stream} = Data) ->
    error_logger:error_msg("Stream Error: ~p ~n", [Error]),
    snatch:disconnected(?MODULE),
    close_stream(Stream),
    {next_state, retrying, Data, [{next_event, cast, connect}]};
handle_event(info, {'$gen_event', {xmlstreamelement, Packet}}, _State, Data) ->
    {keep_state, Data,[{next_event, cast, {received, Packet}}]};
handle_event(Type, Content, State, Data) ->
    case erlang:function_exported(?MODULE, State, 3) of
        true ->
            ?MODULE:State(Type, Content, Data);
        _ ->
            error_logger:error_msg("Unknown Function: ~p~n", [State])
    end.

terminate(_Reason, _StateName, _StateData) ->
    ok.

code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.


close_stream(<<>>) -> ok;
close_stream(Stream) -> fxml_stream:close(Stream).


process_fcm_message(Message, Data) ->
  io:format("~nFCM claw received message from google FCM :~p",[{Message, Data}]),
  process_message_payload(lists:nth(1,Message#xmlel.children)).


process_message_payload(#xmlel{name = <<"data:gcm">>} = Data) ->
  io:format("~n==> processing payloadd : ~p",[Data]),
  Cdata = fxml:get_tag_cdata(Data),
  io:format("~nCdata : ~p",[Cdata]),
  Payload = jsone:decode(Cdata),
  io:format("~n Got FCM payload :~p",[Payload]),
  process_json_payload(Payload);


process_message_payload(El) ->
  io:format("Received unmanaged payload from Google FCM : ~p",[El]),
  ok.


process_json_payload(#{<<"message_type">> := <<"control">>, <<"control_type">> := <<"CONNECTION_DRAINING">>}) ->
  io:format("~nFCm claw, connection drainned",[]),
  pooler:remove_pid(self()),
  {next_state, drainned};


process_json_payload(#{<<"message_type">> := <<"nack">>}) ->
  io:format("~nNACk from FCM",[]),
  ok;


process_json_payload(Unk) ->
  io:format("~nClaw FCM received unmanaged payload :~p",[Unk]),
  ok.
