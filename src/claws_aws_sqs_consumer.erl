-module(claws_aws_sqs_consumer).
-behaviour(gen_server).

-include("snatch.hrl").
-include_lib("erlcloud/include/erlcloud_aws.hrl").

%% API
-export([start_link/2, start_link/6]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% Util functions (also used in tests)
-export([process_messages/4]).

-record(state, {
    aws_config = "" :: erlcloud_aws:aws_config(),
    max_number_of_messages = 1 :: integer(),
    poll_interval = 21000 :: integer(),
    queue :: string(),
    sqs_module :: module(),
    wait_timeout_seconds = 20 :: integer()
}).

-spec start_link(aws_config(), string()) -> {ok, pid()}.
start_link(AwsConfig, QueueName) ->
    gen_server:start_link(?MODULE, {AwsConfig, QueueName}, []).

-spec start_link(aws_config(), integer(), integer(), [string()], module(), integer()) -> {ok, pid()}.
start_link(AwsConfig, MaxNumberOfMessages, PollInterval, QueueName, SqsModule, WaitTimeoutSeconds) ->
    gen_server:start_link(?MODULE, {AwsConfig, MaxNumberOfMessages, PollInterval, QueueName, SqsModule, WaitTimeoutSeconds}, []).

%% Callbacks
init({AwsConfig, QueueName})  ->
    init({AwsConfig, 1, 21000, QueueName, erlcloud_sqs, 20});

init({AwsConfig, MaxNumberOfMessages, PollInterval, Queue, SqsModule, WaitTimeoutSeconds}) ->
    erlang:send_after(0, self(), poll_sqs),
    {ok, #state{
        aws_config = AwsConfig,
        max_number_of_messages = MaxNumberOfMessages,
        poll_interval = PollInterval,
        queue = Queue,
        sqs_module = SqsModule,
        wait_timeout_seconds = WaitTimeoutSeconds}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(poll_sqs, #state{aws_config = AwsConfig, max_number_of_messages = MaxNumberOfMessages, poll_interval = PollInterval, queue = Queue, sqs_module = SqsModule, wait_timeout_seconds = WaitTimeoutSeconds} = State) ->
    Messages = SqsModule:receive_message(Queue, all, MaxNumberOfMessages, none, WaitTimeoutSeconds, AwsConfig),
    process_messages(Messages, SqsModule, Queue, AwsConfig),
    erlang:send_after(PollInterval, self(), poll_sqs),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Util
process_messages(MessageList, SqsModule, QueueName, AwsConfig) ->
    Messages = proplists:get_value(messages, MessageList, []),
    lists:foreach(fun(M) ->
        Body = to_bin(proplists:get_value(body, M, <<"{\"error\": \"Bodyless Message\"}">>)),
        Receipt = proplists:get_value(receipt_handle, M),
        snatch:received(Body, #via{claws = claws_aws_sqs, exchange = QueueName}),
        SqsModule:delete_message(QueueName, Receipt, AwsConfig)
    end,
    Messages).

to_bin(Num) when is_integer(Num) -> integer_to_binary(Num);
to_bin(Num) when is_float(Num) -> float_to_binary(Num, [{decimals, 4}, compact]);
to_bin(Str) when is_list(Str) -> list_to_binary(Str);
to_bin(Bin) when is_binary(Bin) -> Bin;
to_bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_bin(Map) when is_map(Map) -> jsone:encode(Map).
