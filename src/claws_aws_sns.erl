-module(claws_aws_sns).

-behaviour(gen_server).
-behaviour(claws).

-include("snatch.hrl").

-record(state, {
    sns_module :: atom(), %% TODO possibly do module type/callback trick to give better warnings for Dialyzer
    topic_arn :: string()
}).

-type claws_aws_sns_options() :: #{
    access_key_id => string(),
    secret_access_key => string(),
    region => string()
}.

%% API
-export([start_link/1]).

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

-spec start_link(claws_aws_sns_options() | binary()) -> {ok, pid()}.
start_link(Options) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Options, []).

%% Callbacks
init(Options) when is_map(Options) ->
    AccessKeyId = maps:get(access_key_id, Options, os:getenv("AWS_ACCESS_KEY_ID")),
    SecretAccessKey = maps:get(secret_access_key, Options, os:getenv("AWS_SECRET_ACCESS_KEY")),
    Region = maps:get(region, Options, os:getenv("AWS_DEFAULT_REGION")),
    TopicArn = maps:get(topic_arn, Options),
    SnsModule = maps:get(sns_module, Options, erlcloud_sns),

    MissingEnv = lists:any(fun(V) -> V == false end, [AccessKeyId, SecretAccessKey, Region, TopicArn]),

    if
        MissingEnv ->
            {stop, aws_configuration_not_found};
        true ->
            SnsModule:new(AccessKeyId, SecretAccessKey),
            {ok, #state{topic_arn = TopicArn, sns_module = SnsModule}}
    end;

init(TopicArn) when is_binary(TopicArn) ->
    AccessKeyId = os:getenv("AWS_ACCESS_KEY_ID"),
    SecretAccessKey = os:getenv("AWS_SECRET_ACCESS_KEY"),
    Region = os:getenv("AWS_DEFAULT_REGION"),

    MissingEnv = lists:any(fun(V) -> V == false end, [AccessKeyId, SecretAccessKey, Region]),

    if
        MissingEnv ->
            {stop, aws_configuration_not_found};
        true ->
            erlcloud_sns:new(AccessKeyId, SecretAccessKey),
            {ok, #state{topic_arn = TopicArn, sns_module = erlcloud_sns}}
    end.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({send, JID, Data}, #state{topic_arn = TopicArn, sns_module = SnsModule} = State) ->
    case SnsModule:publish_to_topic(TopicArn, Data, JID) of
        {ok, _MessageId} ->
            {noreply, State};
        {error, Reason} ->
            {error, Reason}
    end;

handle_cast({send, JID, Data, ID}, #state{sns_module = SnsModule} = State) ->
    case SnsModule:publish_to_topic(ID, Data, JID) of
        {ok, _MessageId} ->
            {noreply, State};
        {error, Reason} ->
            {error, Reason}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

send(Data, JID) ->
    gen_server:cast(?MODULE, {send, JID, Data}).

send(Data, JID, ID) ->
    gen_server:cast(?MODULE, {send, JID, Data, ID}).

