-module(claws_aws_sns_tests_mocks).


-export([
    init/0,
    new/2,
    new/3,
    publish_to_topic/4,
    send_message/2,
    send_message/3,
    stop/0,
    was_message_sent/2
]).

-define(TABLE, claws_aws_sns_tests_mocks_table).

init() ->
    ets:new(?TABLE, [set, named_table, public]),
    ok.

new(_AccessKeyId, _SecretKeyId) -> {}.

new(_AccessKeyId, _SecretKeyId, _Host) -> {}.

publish_to_topic(_TopicArn, _Data, JID, _Config) ->
    {ok, JID}.

send_message(Data, JID) ->
    ets:insert(?TABLE, {JID, Data}),
    {ok, JID}.

send_message(Data, JID, _ID) ->
    send_message(Data, JID).

was_message_sent(JID, Data) ->
    Messages = ets:lookup(?TABLE, JID),
    lists:any(fun({_JID, D}) -> D == Data end, Messages).

stop() ->
    ets:delete(?TABLE),
    ok.
