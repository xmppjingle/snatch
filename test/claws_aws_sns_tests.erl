-module(claws_aws_sns_tests).

-include_lib("eunit/include/eunit.hrl").
-include("snatch.hrl").

-define(OPTIONS, #{
        access_key_id => "dummy_access_id",
        secret_access_key => "dummy_secret_key",
        sns_module => claws_aws_sns_tests_mocks
    }).

claws_aws_sns_send_message_test_() ->
    {foreach,
     fun setup/0,
     fun stop/1,
     [
        fun test_static_send/0
     ]
    }.

setup() ->
    ok = claws_aws_sns_tests_mocks:init(),
    {ok, _} = application:ensure_all_started(snatch),
    {ok, Pid} = claws_aws_sns:start_link(?OPTIONS),
    Pid.

stop(Pid) ->
    claws_aws_sns_tests_mocks:stop(),
    gen_server:stop(Pid),
    application:stop(snatch).

% Tests
test_static_send() ->
    TopicArn = <<"arn:test-topic">>,
    JID = <<"user@domain.com/home">>,
    Data = <<"<iq id=\"test-bot\" to=\"alice@localhost\" from=\"bob@localhost/pc\" type=\"get\"><query/></iq>">>,
    claws_aws_sns:send(Data, TopicArn, JID),
    [
        ?_assert(claws_aws_sns_tests_mocks:was_message_sent(JID, Data))
    ].
