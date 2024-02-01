-module(claws_aws_sqs).

-behaviour(gen_server).
-behaviour(claws).

-include("snatch.hrl").
-include_lib("erlcloud/include/erlcloud_aws.hrl").

-record(state, {
    aws_config = "" :: erlcloud_aws:aws_config(),
    max_number_of_messages = 1 :: integer(),
    poll_interval = 21000 :: integer(),
    queues :: [string()],
    sqs_module :: module(),
    wait_timeout_seconds = 20 :: integer()
}).

%% API
-export([start_link/1, start_link/6]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% claws callbacks
-export([send/2,
         send/3]).

%% Util functions (also used in tests)
-export([process_messages/1]).

-spec start_link([string()]) -> {ok, pid()}.
start_link(QueueNames) ->
    AwsConfig =
        try erlcloud_aws:auto_config() of
            {ok, Config} -> Config
        catch _:_ ->
            erlcloud_aws:default_config()
        end,
    gen_server:start_link({local, ?MODULE}, ?MODULE, {AwsConfig, QueueNames}, []).

-spec start_link(aws_config(), integer(), integer(), [string()], module(), integer()) -> {ok, pid()}.
start_link(AwsConfig, MaxNumberOfMessages, PollInterval, QueueNames, SqsModule, WaitTimeoutSeconds) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {AwsConfig, MaxNumberOfMessages, PollInterval, QueueNames, SqsModule, WaitTimeoutSeconds}, []).

%% Callbacks
init({AwsConfig, QueueNames})  ->
    init({AwsConfig, 1, 21000, QueueNames, erlcloud_sqs, 20});

init({AwsConfig, MaxNumberOfMessages, PollInterval, Queues, SqsModule, WaitTimeoutSeconds}) ->
    erlang:send_after(0, self(), poll_sqs),
    {ok, #state{
        aws_config = AwsConfig,
        max_number_of_messages = MaxNumberOfMessages,
        poll_interval = PollInterval,
        queues = Queues,
        sqs_module = SqsModule,
        wait_timeout_seconds = WaitTimeoutSeconds}}.

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

handle_cast({received, Messages}, State) ->
    process_messages(Messages),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(poll_sqs, #state{aws_config = AwsConfig, max_number_of_messages = MaxNumberOfMessages, poll_interval = PollInterval, queues = Queues, sqs_module = SqsModule, wait_timeout_seconds = WaitTimeoutSeconds} = State) ->
    MessagesL = [SqsModule:receive_message(Queue, all, MaxNumberOfMessages, none, WaitTimeoutSeconds, AwsConfig) || Queue <- Queues],
    Messages = lists:flatten(MessagesL),
    gen_server:cast(?MODULE, {received, Messages}),
    erlang:send_after(PollInterval, self(), poll_sqs),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

send(Data, JID) ->
    gen_server:cast(?MODULE, {send, JID, Data}).

send(Data, JID, ID) -> %% TODO not sure what to do with the ID in this context
    MessageAttributes = [{<<"Id">>, {string, ID}}],
    gen_server:cast(?MODULE, {send, JID, Data, MessageAttributes}).

%% Util
process_messages(MessageList) ->
    Messages = proplists:get_value(messages, MessageList, []),
    Bodies = [proplists:get_value(body, Msg) || Msg <- Messages],
    Packets = [process_body(list_to_binary(Body)) || Body <- Bodies],
    lists:foreach(fun ({ok, Packet, Via}) -> snatch:received(Packet, Via) end,
                    Packets).

process_body(Body) ->
    case fxml_stream:parse_element(Body) of
        {error, _Reason} ->
            {error, xml_parsing_failed};
        Packet ->
            {ok, Packet, #via{claws = ?MODULE}}
    end.
