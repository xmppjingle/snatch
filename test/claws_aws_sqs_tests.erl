-module(claws_aws_sqs_tests).

-include_lib("erlcloud/include/erlcloud_aws.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("snatch.hrl").

-define(RECV_WAIT, 1000).

claws_aws_sqs_send_message_test_() ->
    {foreach,
     fun setup/0,
     fun stop/1,
     [
        fun test_process_message/0,
        fun test_static_send_receive/0,
        fun test_snatch/0
     ]
    }.

setup() ->
    ok = claws_aws_sqs_tests_mocks:init([]),
    {ok, Pid} = claws_aws_sqs:start_link(#aws_config{}, 1, 21000, [], claws_aws_sqs_tests_mocks, 20),
    Pid.

stop(Pid) ->
    claws_aws_sqs_tests_mocks:stop(),
    exit(Pid, shutdown),
    application:stop(snatch).

test_process_message() ->
    Contents = "<iq id=\"test-bot\" to=\"alice@localhost\" from=\"bob@localhost/pc\" type=\"get\"><query/></iq>",
    Results = claws_aws_sqs_consumer:process_messages(
        [{messages, [[{body, Contents}, {receipt_handle,"YzUyYzA0ZTctMzYwM"}]]}],
        claws_aws_sqs_tests_mocks,
        "Test",
        #aws_config{}
    ),
    Via = #via{claws = claws_aws_sqs},
    [
        ?_assertMatch([{ok, Contents, Via}], Results)
    ].

test_static_send_receive() ->
    QueueName = <<"test-queue">>,
    Message = <<"<test-message/>">>,
    claws_aws_sqs:send(Message, QueueName),
    Results = claws_aws_sqs_tests_mocks:receive_message(QueueName, {}),
    [
        ?_assert(claws_aws_sqs_tests_mocks:was_message_sent(QueueName, Message)),
        ?_assert(lists:member(Message, Results))
    ].

test_snatch() ->
    Contents = <<"<iq id=\"test-bot\" to=\"alice@localhost\" from=\"bob@localhost/pc\" type=\"get\"><query/></iq>">>,
    {ok, _} = snatch:start_link(claws_aws_sqs, self()),
    ok = snatch:send(Contents),
    ok = snatch:received(Contents),
    snatch:stop(),
    [
        ?_assertMatch([{received, Contents, #via{claws = claws_aws_sqs}}|_],
            recv_all([]))
    ].

%% Utils
recv_all(Data) ->
    receive
        D -> recv_all([D|Data])
    after
        ?RECV_WAIT -> Data
    end.
