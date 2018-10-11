-module(claws_apns_worker).
-author("benhur.langoni").

-behaviour(gen_server).

-include("snatch.hrl").

%% gen_server callbacks
-export([ init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

init(ApnsConfig) ->
    {ok, ConnectionPid} = apns:connect(ApnsConfig),
    {ok, #{connection_pid => ConnectionPid}}.

handle_call({push, DeviceId, ApnsTopic, Notification}, _From, State) ->
    #{connection_pid := ConnectionPid} = State,
    Headers = #{apns_topic => ApnsTopic},
    Response = apns:push_notification(ConnectionPid, DeviceId, Notification, Headers),
    snatch:received(Response, #via{jid = DeviceId, exchange = ApnsTopic, claws = claws_apns}),
    error_logger:info_msg("Got APNS response for push[cert]: [~p] for request [~p]", [Response,
        #{connection => ConnectionPid, device => DeviceId, notification => Notification, headers => Headers}]),
    {reply, Response, State};

handle_call({push_token, Token, DeviceId, ApnsTopic, Notification}, _From, State) ->
    #{connection_pid := ConnectionPid} = State,
    Headers = #{apns_topic => ApnsTopic},
    Response = apns:push_notification_token(ConnectionPid, Token, DeviceId, Notification, Headers),
    snatch:received(Response, #via{jid = DeviceId, exchange = ApnsTopic, claws = claws_apns}),
    error_logger:info_msg("Got APNS response for push[token]: [~p] for request [~p]", [Response,
        #{token => Token, connection => ConnectionPid, device => DeviceId,
            notification => Notification, headers => Headers}]),
    {reply, Response, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
