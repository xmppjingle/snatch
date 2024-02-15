-module(claws_aws_sqs).

-behaviour(gen_server).
-behaviour(claws).

-include("snatch.hrl").
-include_lib("erlcloud/include/erlcloud_aws.hrl").

%% API
-export([start_link/1, start_link/2, start_link/3, start_link/7]).

%% gen_server callbacks
-export([code_change/3,
         init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2]).

%% claws callbacks
-export([send/2, send/3]).

-record(state, {
    aws_config = "" :: erlcloud_aws:aws_config(),
    max_number_of_messages = 1 :: integer(),
    poll_interval = 21000 :: integer(),
    queue :: string(),
    sqs_module :: module(),
    wait_timeout_seconds = 20 :: integer()
}).

-type server_name() :: {local, atom()} | {global, term()} | {via, module(), term()}.

-spec start_link(string()) -> {ok, pid()}.
start_link(QueueName) ->
    gen_server:start_link(?MODULE, [QueueName], []).

-spec start_link(server_name(), string()) -> {ok, pid()}.
start_link(ServerName, QueueName) ->
    gen_server:start_link(ServerName, ?MODULE, [QueueName], []).

-spec start_link(server_name(), aws_config(), string()) -> {ok, pid()}.
start_link(ServerName, AwsConfig, QueueName) ->
    gen_server:start_link(ServerName, ?MODULE, [AwsConfig, QueueName], []).

-spec start_link(server_name(), aws_config(), integer(), integer(), string(), module(), integer()) -> {ok, pid()}.
start_link(ServerName, AwsConfig, MaxNumberOfMessages, PollInterval, QueueNames, SqsModule, WaitTimeoutSeconds) ->
    Args = [AwsConfig, MaxNumberOfMessages, PollInterval, QueueNames, SqsModule, WaitTimeoutSeconds],
    gen_server:start_link(ServerName, ?MODULE, Args, []).

%% Callbacks
init([QueueName]) ->
    AwsConfig =
        try erlcloud_aws:auto_config() of
            {ok, Config} -> Config
        catch _:_ ->
            erlcloud_aws:default_config()
        end,
    init([AwsConfig, QueueName]);

init([AwsConfig, QueueName]) ->
    init([AwsConfig, 1, 21000, QueueName, erlcloud_sqs, 20]);

init([AwsConfig, MaxNumberOfMessages, PollInterval, QueueName, SqsModule, WaitTimeoutSeconds]) ->
    State = #state{
        aws_config = AwsConfig,
        max_number_of_messages = MaxNumberOfMessages,
        poll_interval = PollInterval,
        queue = QueueName,
        sqs_module = SqsModule,
        wait_timeout_seconds = WaitTimeoutSeconds
    },
    case string:is_empty(QueueName) of
        false -> erlang:send_after(PollInterval, self(), poll_sqs);
        true -> ok
    end,
    {ok, State}.

%% gen_server
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({send, QueueName, Message}, #state{aws_config = AwsConfig, sqs_module = SqsModule} = State) ->
    case SqsModule:send_message(QueueName, Message, AwsConfig) of
        [{message_id, _MessageId}, {md5_of_message_body, _Md5OfMessageBody}] ->
            {noreply, State};
        ErrorInfo ->
            io:format("error in SQS send_message/3 => ~p~n", [ErrorInfo]),
            {stop, {sqs_send_failed, ErrorInfo}, State}
    end;

handle_cast({send, QueueName, Data, Attributes}, #state{aws_config = AwsConfig, sqs_module = SqsModule} = State) ->
    SQSAttributes = lists:map(fun({Key, {DataType, Value}}) ->
                                  {binary_to_list(Key), [{data_type, DataType}, {string_value, Value}]}
                              end, Attributes),
    case SqsModule:send_message(QueueName, Data, [{message_attributes, SQSAttributes}], AwsConfig) of
        [{message_id, _MessageId}, {md5_of_message_body, _Md5OfMessageBody}] ->
            {noreply, State};
        ErrorInfo ->
            io:format("error in SQS send_message/3 => ~p~n", [ErrorInfo]),
            {stop, {sqs_send_failed, ErrorInfo}, State}
    end;

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

%% Claws callbacks
send(Data, JID) ->
    gen_server:cast(?MODULE, {send, Data, JID}).

send(Data, JID, ID) ->
    gen_server:cast(?MODULE, {send, Data, JID, ID}).

%% Utils
process_messages(MessageList, SqsModule, QueueName, AwsConfig) ->
    Messages = proplists:get_value(messages, MessageList, []),
    lists:foreach(fun(M) ->
        {ok, Packet, Via} = process_body(list_to_binary(proplists:get_value(body, M))),
        Receipt = proplists:get_value(receipt_handle, M),
        snatch:received(Packet, Via),
        SqsModule:delete_message(QueueName, Receipt, AwsConfig)
    end,
    Messages).

process_body(Body) ->
    case fxml_stream:parse_element(Body) of
        {error, _Reason} ->
            {error, xml_parsing_failed};
        Packet ->
            {ok, Packet, #via{claws = claws_aws_sqs}}
    end.
