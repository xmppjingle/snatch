-module(claws_kafka).

-behaviour(gen_server).
-behaviour(claws).

-export([start_link/1,
         stop/1,
         ack/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% claws callbacks
-export([send/2,
         send/3]).

%% brod_group_subscriber callbacks
-export([init/2,
         handle_message/4]).

-include_lib("brod/include/brod.hrl").
-include("snatch.hrl").

-define(KAFKA_CLIENT, client1).
-define(DEFAULT_PARTITION, 0).


start_link(Params) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).


stop(PID) ->
    ok = gen_server:stop(PID).

ack(#kafka_message{offset = Offset}, {Topic, Partition}) ->
    brod:consume_ack(?KAFKA_CLIENT, Topic, Partition, Offset).

init(#{endpoints := Endpoints, % [{"localhost", 9092}]
       in_topics := InTopics} = Opts) ->
    ok = brod:start_client(Endpoints, ?KAFKA_CLIENT),
    case maps:get(out_topic, Opts, undefined) of
        undefined ->
            ok;
        OutTopic ->
            ProdConfig = [],
            ok = brod:start_producer(?KAFKA_CLIENT, OutTopic, ProdConfig)
    end,
    Subscribers = lists:map(fun (InTopic) -> start_subscriber(InTopic, Opts) end,
                            InTopics),
    {ok, Opts#{subscribers => Subscribers}}.

start_subscriber({InTopic, {group, GroupId}}, Opts) ->
    GroupConfig = maps:get(group_config, Opts, default_group_config()),
    ConsumerConfig = maps:get(consumer_config, Opts, default_consumer_config()),
    State = #{topic => InTopic, group => GroupId},
    {ok, PID} = brod_group_subscriber:start_link(?KAFKA_CLIENT, GroupId, [InTopic],
                                                 GroupConfig, ConsumerConfig,
                                                 _MessageType = message,
                                                 _CallbackModule  = ?MODULE,
                                                 _CallbackInitArg = State),
    {brod_group_subscriber, PID};
start_subscriber({InTopic, InPartitions}, Opts) when is_list(InPartitions) ->
    ConsumerConfig = maps:get(consumer_config, Opts, default_consumer_config()),
    AutoAckConfig = maps:get(auto_ack, Opts, true),
    CommitOffsets = [],
    State = #{topic => InTopic,
              partitions => InPartitions,
              auto_ack => AutoAckConfig},
    {ok, PID} = brod_topic_subscriber:start_link(?KAFKA_CLIENT,
                                                 InTopic,
                                                 InPartitions,
                                                 ConsumerConfig,
                                                 CommitOffsets,
                                                 _MessageType = message,
                                                 fun subscriber_callback/3,
                                                 State),
    {brod_topic_subscriber, PID}.


default_group_config() ->
    [{offset_commit_policy, commit_to_kafka_v2},
     {offset_commit_interval_seconds, 5}].


default_consumer_config() ->
    [{begin_offset, earliest}].


%% brod_topic_subscriber:cb_fun()
subscriber_callback(Partition, Msg, #{topic := Topic,
                                      auto_ack := true} = State) ->
    gen_server:cast(?MODULE, {received, Msg, {Topic, Partition}}),
    {ok, ack, State};
subscriber_callback(Partition, Msg, #{topic := Topic,
                                      auto_ack := false} = State) ->
    gen_server:cast(?MODULE, {received, Msg, {Topic, Partition}}),
    {ok, State}.


%% brod_group_subscriber init/2 impl
init(_Topic, #{} = SubscriberState) ->
    {ok, SubscriberState}.


%% brod_group_subscriber handle_message/4 impl
handle_message(Topic, Partition, Msg, State) ->
    gen_server:cast(?MODULE, {received, Msg, {Topic, Partition}}),
    %% TODO: Follows subscriber_callback/3, but what if we crash after ack?
    {ok, ack, State}.


handle_call(_Request, _From, State) ->
    {reply, ignored, State}.


handle_cast({received, #kafka_message{key = _Key, value = Data}, {Topic, _Part}},
            #{raw := true} = Opts) ->
    Via = #via{claws = ?MODULE, exchange = Topic},
    snatch:received(Data, Via),
    {noreply, Opts};

handle_cast({received, #kafka_message{key = _Key, value = XML}, {_Topic, _Part}},
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

handle_cast({received, #kafka_message{key = _Key, value = XML}, {_Topic, _Part}},
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
    {noreply, Opts};

handle_cast(_Msg, State) -> 
    {noreply, State}.


handle_info(_Info, Opts) ->
    io:format("info => ~p~n", [_Info]),
    {noreply, Opts}.


terminate(_Reason, #{subscribers := Subscribers}) ->
    ok = lists:foreach(fun({SubscriberMod, PID}) ->
        ok = SubscriberMod:stop(PID)
    end, Subscribers),
    ok = brod:stop_client(?KAFKA_CLIENT),
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


send(Data, JID) ->
    send(Data, JID, undefined).


send(Data, JID, ID) ->
    gen_server:cast(?MODULE, {send, Data, JID, ID}).
