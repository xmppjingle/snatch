-module(claws_aws_sns).

-behaviour(gen_server).
-behaviour(claws).

-include("snatch.hrl").
-include_lib("erlcloud/include/erlcloud_aws.hrl").

-record(state, {
    sns_module :: atom(),
    aws_config = erlcloud_aws:aws_config()
}).


-type claws_aws_sns_options() :: #{
    access_key_id => string(),
    secret_access_key => string()
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
    SnsModule = maps:get(sns_module, Options, erlcloud_sns),
    AccessKeyId = maps:get(access_key_id, Options, os:getenv("AWS_ACCESS_KEY_ID")),
    SecretAccessKey = maps:get(secret_access_key, Options, os:getenv("AWS_SECRET_ACCESS_KEY")),
    SnsPort = maps:get(sns_port, Options, undefined),
    SnsScheme = maps:get(sns_scheme, Options, undefined),

    MissingEnv = lists:any(fun(V) -> V == false end, [AccessKeyId, SecretAccessKey]),

    if MissingEnv ->
        case erlcloud_aws:profile() of
            {ok, BaseConfig} ->
                Config = enrich_aws_config(SnsPort, SnsScheme, BaseConfig),
                {ok, #state{aws_config = Config, sns_module = SnsModule}};
            {error, _Reason} ->
                {stop, aws_configuration_not_found}
        end;
        true ->
            BaseConfig = case maps:get(sns_host, Options, undefined) of
                undefined ->
                    SnsModule:new(AccessKeyId, SecretAccessKey);
                Host ->
                    SnsModule:new(AccessKeyId, SecretAccessKey, Host)
            end,
            Config = enrich_aws_config(SnsPort, SnsScheme, BaseConfig),
            {ok, #state{aws_config = Config, sns_module = SnsModule}}
    end;

init([]) ->
    AccessKeyId = os:getenv("AWS_ACCESS_KEY_ID"),
    SecretAccessKey = os:getenv("AWS_SECRET_ACCESS_KEY"),
    Config = erlcloud_sns:new(AccessKeyId, SecretAccessKey),

    MissingEnv = lists:any(fun(V) -> V == false end, [AccessKeyId, SecretAccessKey]),

    if
        MissingEnv ->
            {stop, aws_configuration_not_found};
        true ->
            {ok, #state{aws_config = Config,sns_module = erlcloud_sns}}
    end.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({send, TopicArn, Message}, #state{aws_config = AwsConfig, sns_module = SnsModule} = State) ->
    case SnsModule:publish_to_topic(TopicArn, Message, AwsConfig) of
        {ok, _MessageId} ->
            {noreply, State};
        {error, Reason} ->
            {error, Reason}
    end;

handle_cast({send, TopicArn, Message, Subject}, #state{aws_config = AwsConfig, sns_module = SnsModule} = State) ->
    case SnsModule:publish_to_topic(TopicArn, Message, Subject, AwsConfig) of
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

%% Util
enrich_aws_config(SnsPort, SnsScheme, BaseConfig) ->
    case {SnsPort, SnsScheme} of
        {undefined, undefined} -> BaseConfig;
        {Port, undefined} -> BaseConfig#aws_config{sns_port = Port};
        {undefined, Scheme} -> BaseConfig#aws_config{sns_scheme = Scheme};
        {Port, Scheme} -> BaseConfig#aws_config{sns_port = Port, sns_scheme = Scheme}
    end.
