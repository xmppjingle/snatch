-module(claws_aws_sqs_tests).

-include_lib("eunit/include/eunit.hrl").
-include("snatch.hrl").

-define(RECV_WAIT, 1000).
-define(OPTIONS, #{
        access_key_id => "dummy_access_id",
        secret_access_key => "dummy_secret_key",
        region => "dummy_region",
        queue_url => "dummy_queue_url",
        sqs_module => claws_aws_sqs_tests_mocks
    }).

claws_aws_sqs_send_message_test_() ->
    {foreach,
     fun setup/0,
     fun stop/1,
     [
        fun test_static_send_receive/0,
        fun test_snatch/0
     ]
    }.

setup() ->
    rand:seed(exsplus),
    rand:uniform(),
    ok = claws_aws_sqs_tests_mocks:init(),
    {ok, _} = application:ensure_all_started(snatch),
    {ok, Pid} = claws_aws_sqs:start_link(?OPTIONS),
    Pid.

stop(Pid) ->
    claws_aws_sqs_tests_mocks:stop(),
    gen_server:stop(Pid),
    application:stop(snatch).

% Tests
test_static_send_receive() ->
    QueueName = <<"test-queue">>,
    Message = <<"<test-message/>">>,
    claws_aws_sqs:send(Message, QueueName),
    {ok, Results} = claws_aws_sqs_tests_mocks:receive_message(QueueName, {}),
    [
        ?_assert(claws_aws_sqs_tests_mocks:was_message_sent(QueueName, Message)),
        ?_assert(lists:member(Message, Results))
    ].

%% TODO
test_snatch() ->
    Contents = <<"<iq id=\"test-bot\" to=\"alice@localhost\" from=\"bob@localhost/pc\" type=\"get\"><query/></iq>">>,
    {ok, _} = snatch:start_link(claws_aws_sqs, self()),
    ok = snatch:send(Contents, <<"TestQueue">>),
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
