-module(claws_aws_sqs).

-behaviour(supervisor).
-behaviour(claws).

-include("snatch.hrl").
-include_lib("erlcloud/include/erlcloud_aws.hrl").

-define(PREFIX, "claws_aws_sqs_").
-define(SENDER_PROC, claws_aws_sqs_sender_proc).

%% API
-export([start_link/1, start_link/2, start_link/6]).

%% supervisor callbacks
-export([init/1]).

%% claws callbacks
-export([send/2,
         send/3]).

-spec start_link([string()]) -> {ok, pid()}.
start_link(QueueNames) ->
    AwsConfig =
        try erlcloud_aws:auto_config() of
            {ok, Config} -> Config
        catch _:_ ->
            erlcloud_aws:default_config()
        end,
    supervisor:start_link({local, ?MODULE}, ?MODULE, {AwsConfig, QueueNames}).

-spec start_link(aws_config(), [string()]) -> {ok, pid()}.
start_link(AwsConfig, QueueNames) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, {AwsConfig, QueueNames}).

-spec start_link(aws_config(), integer(), integer(), [string()], module(), integer()) -> {ok, pid()}.
start_link(AwsConfig, MaxNumberOfMessages, PollInterval, QueueNames, SqsModule, WaitTimeoutSeconds) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, {AwsConfig, MaxNumberOfMessages, PollInterval, QueueNames, SqsModule, WaitTimeoutSeconds}).

%% Callbacks
init({AwsConfig, QueueNames}) ->
    Config = #{
        aws_config => AwsConfig,
        sqs_module => erlcloud_sqs
    },
    put(config, Config),
    SupFlags = #{strategy => one_for_one, intensity => 1, period => 5},
    ChildSpecs = lists:map(fun(Q) -> create_consumer_child_spec([AwsConfig, Q]) end, QueueNames),
    SenderPid = spawn_link(fun () ->
        put(config, Config),
        send_loop()
    end),
    register(?SENDER_PROC, SenderPid),
    {ok, {SupFlags, ChildSpecs}};

init({AwsConfig, MaxNumberOfMessages, PollInterval, Queues, SqsModule, WaitTimeoutSeconds}) ->
    Config = #{
        aws_config => AwsConfig,
        sqs_module => erlcloud_sqs
    },
    SupFlags = #{strategy => one_for_one, intensity => 1, period => 5},
    ChildSpecs = lists:map(fun(Q) ->
        Args = [AwsConfig, Q, MaxNumberOfMessages, PollInterval, Queues, SqsModule, WaitTimeoutSeconds],
        create_consumer_child_spec(Args)
    end, Queues),
    SenderPid = spawn_link(fun () ->
        put(config, Config),
        send_loop()
    end),
    register(?SENDER_PROC, SenderPid),
    {ok, {SupFlags, ChildSpecs}}.

%% Claws callbacks
send(Data, JID) ->
    ?SENDER_PROC ! {send, Data, JID}.

send(Data, JID, ID) ->
    ?SENDER_PROC ! {send, Data, JID, ID}.

create_consumer_child_spec([AwsConfig, QueueName]) ->
    #{id => ?PREFIX ++ QueueName,
      start => {claws_aws_sqs_consumer, start_link, [AwsConfig, QueueName]},
      restart => permanent,
      shutdown => 5000,
      type => worker,
      modules => [claws_aws_sqs_consumer]};

create_consumer_child_spec([AwsConfig, QueueName, MaxNumberOfMessages, PollInterval, Queues, SqsModule, WaitTimeoutSeconds]) ->
    #{id => ?PREFIX ++ QueueName,
      start => {claws_aws_sqs_consumer, start_link, [AwsConfig, QueueName,  MaxNumberOfMessages, PollInterval, Queues, SqsModule, WaitTimeoutSeconds]},
      restart => permanent,
      shutdown => 5000,
      type => worker,
      modules => [claws_aws_sqs_consumer]}.

proc_send(Data, JID) ->
    #{aws_config := AwsConfig, sqs_module := SqsModule} = get(config),
    case SqsModule:send_message(JID, Data, AwsConfig) of
        [{message_id, MessageId}, {md5_of_message_body, _Md5OfMessageBody}] ->
            {ok, MessageId};
        ErrorInfo ->
            {error, ErrorInfo}
    end.

proc_send(Data, JID, ID) ->
    #{aws_config := AwsConfig, sqs_module := SqsModule} = get(config),
    MessageAttributes = [{<<"Id">>, {string, ID}}],
    SQSAttributes = lists:map(fun({Key, {DataType, Value}}) ->
                                  {binary_to_list(Key), [{data_type, DataType}, {string_value, Value}]}
                              end, MessageAttributes),
    case SqsModule:send_message(JID, Data, [{message_attributes, SQSAttributes}], AwsConfig) of
        [{message_id, MessageId}, {md5_of_message_body, _Md5OfMessageBody}] ->
            {ok, MessageId};
        ErrorInfo ->
            {error, ErrorInfo}
    end.

send_loop() ->
    receive
        {send, Data, JID} ->
            proc_send(Data, JID),
            send_loop();
        {send, Data, JID, ID} ->
            proc_send(Data, JID, ID),
            send_loop();
        _ ->  send_loop()
    end.
