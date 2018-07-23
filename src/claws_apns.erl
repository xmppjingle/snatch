-module(claws_apns).
-author("benhur.langoni").

-behaviour(supervisor).
-behaviour(claws).

%% Application callbacks
-export([ start_link/1, send/2, send/3, push/3, push_token/4]).

%% Supervisor callbacks
-export([ init/1]).

-define(DEFAULT_TOPIC, <<"push">>).

start_link(ApnsConfig) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, ApnsConfig).

init(ApnsConfig) ->
    WPoolOptions  = [ {overrun_warning, infinity}
        , {overrun_handler, {error_logger, warning_report}}
        , {workers, maps:get(pool_size, ApnsConfig, 20)}
        , {worker, {claws_apns_worker, ApnsConfig}}
    ],

    SupFlags = #{ strategy  => one_for_one
        , intensity => 1000
        , period    => 3600
    },

    Children = [#{ id       => wpool
        , start    => {wpool, start_pool, [claws_apns_pool, WPoolOptions]}
        , restart  => permanent
        , shutdown => 5000
        , type     => supervisor
        , modules  => [wpool]
    }],

    {ok, {SupFlags, Children}}.

push(Data, DeviceId, ApnsTopic) ->
    wpool:call(claws_apns_pool, {push, DeviceId, ApnsTopic, Data}).

push_token(Token, Data, DeviceId, ApnsTopic) ->
    wpool:call(claws_apns_pool, {push_token, Token, DeviceId, ApnsTopic, Data}).

send(Data, DeviceId) ->
    push(Data, DeviceId, ?DEFAULT_TOPIC).

send(Data, DeviceId, ApnsTopic) ->
    push(DeviceId, Data, ApnsTopic).