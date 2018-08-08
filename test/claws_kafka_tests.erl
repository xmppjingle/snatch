-module(claws_kafka_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("fast_xml/include/fxml.hrl").
-include_lib("brod/include/brod.hrl").
-include("snatch.hrl").

-define(KAFKA_CLIENT, client2).
-define(ENDPOINTS, [{"localhost", 9092}]).
-define(TOPIC_OUT, <<"xmpp.out">>).
-define(TOPIC_IN, <<"xmpp.in">>).
-define(PARTITION, 0).

-define(WAIT_FOR_KAFKA, 2000).
-define(TIME_TO_START, 1000).

subscriber(Partition, Msg, ShellPid = CallbackState) ->
    ShellPid ! {received, Msg, Partition},
    {ok, ack, CallbackState}.

connect() ->
    {ok, _} = application:ensure_all_started(snatch),
    ok = brod:start_client(?ENDPOINTS, ?KAFKA_CLIENT),
    ok = brod:start_producer(?KAFKA_CLIENT, ?TOPIC_OUT, []),
    {ok, PID} = brod_topic_subscriber:start_link(?KAFKA_CLIENT,
                                                 ?TOPIC_IN,
                                                 [?PARTITION],
                                                 [{begin_offset, earliest}],
                                                 [],
                                                 message,
                                                 fun subscriber/3,
                                                 self()),
    timer:sleep(?TIME_TO_START),
    recv_all([]), % cleaning
    {ok, PID}.

send(Data) ->
    ok = brod:produce_sync(?KAFKA_CLIENT,
                           ?TOPIC_OUT,
                           ?PARTITION,
                           _Key = <<"test">>,
                           Data),
    ok.

recv_all(Data) ->
    receive
        D -> recv_all([D|Data])
    after
        ?WAIT_FOR_KAFKA -> Data
    end.

disconnect(TopicPID) ->
    ok = brod_topic_subscriber:stop(TopicPID),
    ok = brod:stop_client(?KAFKA_CLIENT),
    ok.

send_test_() ->
    {timeout, 60000, fun() ->
        {ok, TopicPID} = connect(),
        {ok, _} = snatch:start_link(claws_kafka, self()),
        Params = #{
            endpoints => ?ENDPOINTS,
            in_topics => [{?TOPIC_OUT, [?PARTITION]}],
            out_topics => [?TOPIC_IN],
            out_partition => ?PARTITION,
            trimmed => false
        },
        {ok, PID} = claws_kafka:start_link(Params),
        timer:sleep(?TIME_TO_START),

        ok = snatch:send(<<"<presence/>">>,
                         <<"irc.example.com">>,
                         ?TOPIC_IN),
        ok = snatch:send(<<"<presence/>">>, <<"irc.example.com">>),
        ok = snatch:send(<<"<presence/>">>, <<>>),
        Key1 = <<"irc.example.com">>,
        Key2 = <<"irc.example.com">>,
        Key3 = undefined,
        Value = <<"<presence/>">>,
        ?assertMatch([{received, #kafka_message{key = Key3, value = Value}, 0},
                      {received, #kafka_message{key = Key2, value = Value}, 0},
                      {received, #kafka_message{key = Key1, value = Value}, 0}|_],
                     recv_all([])),

        ok = claws_kafka:stop(PID),
        ok = snatch:stop(),
        ok = disconnect(TopicPID),
        ok
    end}.

message_raw_test_() ->
    {timeout, 60000, fun() ->
        {ok, TopicPID} = connect(),
        {ok, _} = snatch:start_link(claws_kafka, self()),
        Params = #{
            endpoints => ?ENDPOINTS,
            in_topics => [{?TOPIC_OUT, [?PARTITION]}],
            out_topics => [?TOPIC_IN],
            raw => true
        },
        {ok, PID} = claws_kafka:start_link(Params),
        timer:sleep(?TIME_TO_START),

        Text = <<"This is a text">>,
        ok = send(Text),
        ?assertMatch([{received, Text, #via{claws = claws_kafka}}|_],
                     recv_all([])),

        ok = claws_kafka:stop(PID),
        ok = snatch:stop(),
        ok = disconnect(TopicPID),
        ok
    end}.

message_test_() ->
    {timeout, 60000, fun() ->
        {ok, TopicPID} = connect(),
        {ok, _} = snatch:start_link(claws_kafka, self()),
        Params = #{
            endpoints => ?ENDPOINTS,
            in_topics => [{?TOPIC_OUT, [?PARTITION]}],
            out_topics => [?TOPIC_IN],
            trimmed => false
        },
        {ok, PID} = claws_kafka:start_link(Params),
        timer:sleep(?TIME_TO_START),

        ok = send(<<"<presence>
                    </presence>">>),
        ?assertMatch([{received, #xmlel{name = <<"presence">>,
                                        children = [_]},
                       #via{claws = claws_kafka}}|_],
                     recv_all([])),

        ok = claws_kafka:stop(PID),
        ok = snatch:stop(),
        ok = disconnect(TopicPID),
        ok
    end}.

message_trimmed_test_() ->
    {timeout, 60000, fun() ->
        {ok, TopicPID} = connect(),
        {ok, _} = snatch:start_link(claws_kafka, self()),
        Params = #{
            endpoints => ?ENDPOINTS,
            in_topics => [{?TOPIC_OUT, [?PARTITION]}],
            out_topics => [?TOPIC_IN],
            out_partition => ?PARTITION,
            trimmed => true
        },
        {ok, PID} = claws_kafka:start_link(Params),
        timer:sleep(?TIME_TO_START),

        ok = send(<<"<presence>
                    </presence>">>),
        ?assertMatch([{received, #xmlel{name = <<"presence">>,
                                        children = []},
                       #via{claws = claws_kafka}}|_],
                     recv_all([])),

        ok = claws_kafka:stop(PID),
        ok = snatch:stop(),
        ok = disconnect(TopicPID),
        ok
    end}.
