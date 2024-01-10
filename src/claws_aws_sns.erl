-module(claws_aws_sns).

-behaviour(gen_server).
-behaviour(claws).

-include("snatch.hrl").
-include_lib("erlcloud/include/erlcloud_aws.hrl").

-record(state, {
    sns_module :: module(),
    aws_config = erlcloud_aws:aws_config()
}).

%% API
-export([start_link/0, start_link/1, start_link/2]).

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

-spec start_link() -> {ok, pid()}.
start_link() ->
    AwsConfig =
        try
            {ok, Config} = erlcloud_aws:auto_config(),
            Config
        catch _ ->
            erlcloud_aws:default_config()
        end,
    gen_server:start_link({local, ?MODULE}, ?MODULE, {AwsConfig}, []).

-spec start_link(aws_config()) -> {ok, pid()}.
start_link(AwsConfig) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {AwsConfig}, []).

-spec start_link(aws_config(), module()) -> {ok, pid()}.
start_link(AwsConfig, SnsModule) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {AwsConfig, SnsModule}, []).

%% Callbacks
init({AwsConfig}) ->
    init({AwsConfig, erlcloud_sns});

init({AwsConfig, SnsModule}) ->
    {ok, #state{aws_config = AwsConfig, sns_module = SnsModule}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({send, TopicArn, Message}, #state{aws_config = AwsConfig, sns_module = SnsModule} = State) ->
    SnsModule:publish_to_topic(TopicArn, Message, undefined, AwsConfig),
    {noreply, State};

handle_cast({send, TopicArn, Message, Subject}, #state{aws_config = AwsConfig, sns_module = SnsModule} = State) ->
    SnsModule:publish_to_topic(TopicArn, Message, Subject, AwsConfig),
    {noreply, State};

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
