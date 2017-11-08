-module(claws_kafka_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("fast_xml/include/fxml.hrl").
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

message_test_() ->
    {timeout, 60000, fun() ->
        {ok, TopicPID} = connect(),
        {ok, _} = snatch:start_link(claws_kafka, self()),
        Params = #{
            endpoints => ?ENDPOINTS,
            in_topics => [{?TOPIC_OUT, [?PARTITION]}],
            out_topic => ?TOPIC_IN,
            out_partition => ?PARTITION,
            trimmed => false
        },
        {ok, PID} = claws_kafka:start_link(Params),
        timer:sleep(?TIME_TO_START),

        ok = send(<<"<presence/>">>),
        ?assertMatch([{received, #xmlel{name = <<"presence">>},
                       #via{claws = claws_kafka}}|_],
                     recv_all([])),

        ok = claws_kafka:stop(PID),
        ok = snatch:stop(),
        ok = disconnect(TopicPID),
        ok
    end}.
