-module(claws_rabbitmq).

-behaviour(gen_server).
-behaviour(claws).

-export([start_link/1, register/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).
-export([send/2, send/3, publish/1, publish/2]).

-include_lib("fast_xml/include/fxml.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").
-include("snatch.hrl").

-record(state, {
    jid,
    channel,
    connection,
    direct_queue,
    fanout_queue
}).

-define(EXCHANGE_DIRECT, <<"xmpp_direct">>).
-define(EXCHANGE_FANOUT, <<"xmpp_fanout">>).
-define(DIRECT, <<"direct">>).
-define(FANOUT, <<"fanout">>).

-define(DEFAULT_USERNAME, <<"guest">>).
-define(DEFAULT_PASSWORD, <<"guest">>).

start_link(Params) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).

register(SocketConnection) ->
    gen_server:call(?MODULE, {register, SocketConnection}).

init(#{jid := JID, host := Host} = Opts) ->
    Username = maps:get(username, Opts, ?DEFAULT_USERNAME),
    Password = maps:get(password, Opts, ?DEFAULT_PASSWORD),
    AmqpNetwork = #amqp_params_network{host = Host, username = Username,
                                       password = Password},
    State = case amqp_connection:start(AmqpNetwork) of
        {ok, Connection} ->
            case amqp_connection:open_channel(Connection) of
                {ok, Channel} ->
                    create_bind_queues(#state{jid = JID, channel = Channel,
                                              connection = Connection});
                _E ->
                    error_logger:error_msg("Could Not Open RabbitMQ Channel: ~p~n", [_E]),
                    #state{}
            end;            
        _E -> 
            error_logger:error_msg("Could Not Start RabbitMQ Connection: ~p~n", [_E]),
            #state{}
    end,    
    {ok, State}.

create_bind_queues(#state{channel = Channel, jid = JID} = S) ->
    BareJID = snatch_jid:to_bare(JID),
    PID = whereis(?MODULE),
    [DirectQueue, EventQueue] = lists:map(fun({Exchange, Type}) ->
        Opts = #'exchange.declare'{exchange = Exchange, type = Type},
        #'exchange.declare_ok'{} = amqp_channel:call(Channel, Opts),
        Name = <<Type/binary, ":", JID/binary>>,
        {Queue, _} = declare_bind_and_consume(Channel, Name, Exchange,
                                              [JID, BareJID], PID),
        Queue
    end, [{?EXCHANGE_DIRECT, ?DIRECT}, {?EXCHANGE_FANOUT, ?FANOUT}]),

    snatch:connected(?MODULE),

    S#state{direct_queue = DirectQueue, fanout_queue = EventQueue}.

declare_bind_and_consume(Channel, Name, Exchange, Routes, Listener) ->
    #'queue.declare_ok'{queue = Queue} =
        amqp_channel:call(Channel, #'queue.declare'{queue = Name}),
    lists:foreach(fun(R) ->
        #'queue.bind_ok'{} =
        amqp_channel:call(Channel, #'queue.bind'{queue = Queue,
                                                 exchange = Exchange,
                                                 routing_key = R})
    end, Routes),
    #'basic.consume_ok'{consumer_tag = Tag} =
        amqp_channel:subscribe(Channel, #'basic.consume'{queue = Queue},
                               Listener),
    {Queue, Tag}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.


handle_cast({send, Data, JID}, State) ->
    amqp_channel:cast(State#state.channel,
                      #'basic.publish'{exchange = ?EXCHANGE_DIRECT, 
                                       routing_key = JID},
                      #amqp_msg{props = #'P_basic'{}, payload = Data}),
    {noreply, State};

handle_cast({send, Data, JID, ID}, State) ->
    amqp_channel:cast(State#state.channel,
                      #'basic.publish'{exchange = ?EXCHANGE_DIRECT,
                                       routing_key = JID},
                      #amqp_msg{props = #'P_basic'{correlation_id = ID},
                                payload = Data}),
    {noreply, State};

handle_cast({publish, Data, JID}, State) ->
    amqp_channel:cast(State#state.channel,
                      #'basic.publish'{exchange = ?EXCHANGE_FANOUT,
                                       routing_key = JID},
                      #amqp_msg{props = #'P_basic'{}, payload = Data}),
    {noreply, State};

handle_cast({publish, Data}, State) ->
    amqp_channel:cast(State#state.channel,
                      #'basic.publish'{exchange = ?EXCHANGE_FANOUT},
                      #amqp_msg{props = #'P_basic'{}, payload = Data}),
    {noreply, State};

handle_cast(_Msg, State) -> 
    {noreply, State}.


handle_info({#'basic.deliver'{delivery_tag = Tag, exchange = Exchange,
                              routing_key = Key},
             #amqp_msg{props = #'P_basic'{correlation_id = ID},
                       payload = Payload}},
             State) ->
    snatch:received(Payload, #via{jid = Key, exchange = Exchange,
                                  claws = ?MODULE, id = ID}),
    amqp_channel:cast(State#state.channel, #'basic.ack'{delivery_tag = Tag}),
    {noreply, State};

handle_info({#'basic.deliver'{delivery_tag = Tag, exchange = Exchange,
                              routing_key = Key}, Message}, State) ->
    snatch:received(Message#amqp_msg.payload,
                    #via{jid = Key, exchange = Exchange, claws = ?MODULE}),
    amqp_channel:cast(State#state.channel, #'basic.ack'{delivery_tag = Tag}),
    {noreply, State};
        
handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

handle_info({'DOWN', _ConnectionRef, process, _Connection, _Reason},
            State) ->
    {stop, down, State};

handle_info(#'basic.cancel_ok'{}, State) ->
    {noreply, normal, State};

handle_info(shutdown, State) ->
    {stop, normal, State};

handle_info(_Info, State) ->
    {noreply, State}.


terminate(_Reason, #state{channel = Channel, connection = Connection}) ->
    if
        is_pid(Channel) -> amqp_channel:close(Channel);
        true -> pass
    end,
    if
        is_pid(Connection) -> amqp_connection:close(Connection);
        true -> pass
    end,
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


send(Data, JID) ->
    gen_server:cast(?MODULE, {send, Data, JID}).


send(Data, JID, ID) ->
    gen_server:cast(?MODULE, {send, Data, JID, ID}).


publish(Data, JID) ->
    gen_server:cast(?MODULE, {publish, Data, JID}).


publish(Data) ->
    gen_server:cast(?MODULE, {publish, Data}).
