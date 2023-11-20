-module(claws_aws_sqs_tests_mocks).

-export([
    init/1,
    new/2,
    receive_message/2,
    send_message/3,
    send_message/4,
    stop/0,
    was_message_sent/2
]).

-define(TABLE, claws_aws_sqs_tests_mocks_table).

init([]) ->
    ets:new(?TABLE, [set, named_table, public]),
    ok.

new(_Access, _Secret) ->
    {}.

send_message(QueueName, Message, _AwsConfig) ->
    ets:insert(?TABLE, {QueueName, Message}),
    {ok, {message_id, "MockMessageId"}}.

send_message(QueueName, Message, _MsgAttrs, _AwsConfig) ->
    ets:insert(?TABLE, {QueueName, Message}),
    {ok, {message_id, "MockMessageId"}}.

receive_message(QueueName, _AwsConfig) ->
    Messages = ets:lookup(?TABLE, QueueName),
    Results = [claws_aws_sqs:process_message(Message) || Message <- Messages],
    case lists:any(fun
        ({error, _Reason}) -> true;
        (_) -> false
    end, Results) of
        true -> {error, process_message_failed};
        _ -> {ok, Results}
    end.

was_message_sent(QueueName, Message) ->
    Messages = ets:lookup(?TABLE, QueueName),
    lists:any(fun({_QueueName, Msg}) -> Msg == Message end, Messages).

stop() ->
    ets:delete(?TABLE),
    ok.
