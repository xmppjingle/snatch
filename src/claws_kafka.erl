-module(claws_kafka).

-behaviour(gen_server).
-behaviour(claws).

-export([start_link/1,
         stop/1]).
% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).
% claws callbacks
-export([send/2,
         send/3]).

-include_lib("brod/include/brod.hrl").
-include("snatch.hrl").

-define(KAFKA_CLIENT, client1).
-define(DEFAULT_PARTITION, 0).


start_link(Params) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).


stop(PID) ->
    ok = gen_server:stop(PID).


subscriber_callback(Partition, Msg, CallbackState) ->
    gen_server:cast(?MODULE, {received, Msg, Partition}),
    {ok, ack, CallbackState}.


init(#{endpoints := Endpoints, % [{"localhost", 9092}]
       in_topics := InTopics,
       out_topic := OutTopic} = Opts) ->
    ok = brod:start_client(Endpoints, ?KAFKA_CLIENT),
    ProdConfig = [],
    ok = brod:start_producer(?KAFKA_CLIENT, OutTopic, ProdConfig),
    ConsumerConfig = [{begin_offset, earliest}],
    CommitOffsets = [],
    SubscriberCallbackFun = fun subscriber_callback/3,
    PIDs = lists:map(fun({InTopic, InPartitions}) ->
        {ok, PID} = brod_topic_subscriber:start_link(?KAFKA_CLIENT,
                                                     InTopic,
                                                     InPartitions,
                                                     ConsumerConfig,
                                                     CommitOffsets,
                                                     _MessageType = message,
                                                     SubscriberCallbackFun,
                                                     _CallbackState = self()),
        PID
    end, InTopics),
    {ok, Opts#{pids => PIDs}}.


handle_call(_Request, _From, State) ->
    {reply, ignored, State}.


handle_cast({received, #kafka_message{key = _Key, value = Data}, _Partition},
            #{raw := true} = Opts) ->
    Via = #via{claws = ?MODULE},
    snatch:received(Data, Via),
    {noreply, Opts};

handle_cast({received, #kafka_message{key = _Key, value = XML}, _Partition},
            #{trimmed := true} = Opts) ->
    case fxml_stream:parse_element(XML) of
        {error, _Error} ->
            io:format("error => ~p~n", [_Error]);
        Packet ->
            From = snatch_xml:get_attr(<<"from">>, Packet),
            To = snatch_xml:get_attr(<<"to">>, Packet),
            Via = #via{jid = From, exchange = To, claws = ?MODULE},
            TrimmedPacket = snatch_xml:clean_spaces(Packet),
            snatch:received(TrimmedPacket, Via)
    end,
    {noreply, Opts};

handle_cast({received, #kafka_message{key = _Key, value = XML}, _Partition},
            Opts) ->
    case fxml_stream:parse_element(XML) of
        {error, _Error} ->
            io:format("error => ~p~n", [_Error]);
        Packet ->
            From = snatch_xml:get_attr(<<"from">>, Packet),
            To = snatch_xml:get_attr(<<"to">>, Packet),
            Via = #via{jid = From, exchange = To, claws = ?MODULE},
            snatch:received(Packet, Via)
    end,
    {noreply, Opts};

handle_cast({send, Data, JID, ID},
            #{out_topic := OutTopic} = Opts) ->
    Partition = maps:get(out_partition, Opts, ?DEFAULT_PARTITION),
    JIDBin = if is_binary(JID) -> JID; true -> <<"unknown">> end,
    IDBin = if is_binary(ID) -> ID; true -> <<"no-id">> end,
    Key = <<JIDBin/binary, ".", IDBin/binary>>,
    ok = brod:produce_sync(?KAFKA_CLIENT, OutTopic, Partition, Key, Data),
    {noreply, Opts}.


handle_info(_Info, Opts) ->
    io:format("info => ~p~n", [_Info]),
    {noreply, Opts}.


terminate(_Reason, #{pids := PIDs}) ->
    ok = lists:foreach(fun(PID) ->
        ok = brod_topic_subscriber:stop(PID)
    end, PIDs),
    ok = brod:stop_client(?KAFKA_CLIENT),
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


send(Data, JID) ->
    send(Data, JID, undefined).


send(Data, JID, ID) ->
    gen_server:cast(?MODULE, {send, Data, JID, ID}).
