-module(rabbit_claws).
-behaviour(gen_server).

-export([start_link/1, publish/1, register/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("amqp_client.hrl").
-record(state, {channel, connection, queue, consumer_tag, socket_connections}).
-define(EVENTS_EXCHANGE, <<"jid">>).

start_link(Args) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

publish(Message) ->
	gen_server:call(?MODULE, {publish, Message}).

register(SocketConnection) ->
	gen_server:call(?MODULE, {register, SocketConnection}).

init(_Args) ->
	{ok, Connection} = amqp_connection:start(#amqp_params_network{}),
	{ok, Channel} = amqp_connection:open_channel(Connection),
	#'exchange.declare_ok'{} = amqp_channel:call(Channel,
		#'exchange.declare'{exchange = ?EVENTS_EXCHANGE, type = <<"fanout">>}),
	#'queue.declare_ok'{queue = Queue} = amqp_channel:call(Channel, 
		#'queue.declare'{}),
	#'queue.bind_ok'{} = amqp_channel:call(Channel,
		#'queue.bind'{queue = Queue, exchange = ?EVENTS_EXCHANGE}),
	#'basic.consume_ok'{consumer_tag = Tag} = 
		amqp_channel:call(Channel, #'basic.consume'{queue = Queue}),
	{ok, #state{queue = Queue, channel = Channel, 
		connection = Connection, consumer_tag = Tag,
		socket_connections = []}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({publish, Message},State) ->
	amqp_channel:cast(State#state.channel,
		#'basic.publish'{exchange = ?EVENTS_EXCHANGE},
		#amqp_msg{props = #'P_basic'{}, payload = 
		    Message}),
	{noreply, State};

handle_cast({register, SocketConnection},State) ->
	SocketConnections = [SocketConnection | State#state.socket_connections],
	{noreply,State#state{socket_connections=SocketConnections}};

handle_cast(_Msg, State) ->	
    {noreply, State}.

handle_info({#'basic.deliver'{delivery_tag = Tag}, Message}, State) ->
	io:format("Deliver: ~p~n", [Message#amqp_msg.payload]),
	amqp_channel:cast(State#state.channel, #'basic.ack'{delivery_tag = Tag}),
	{noreply, State};
		
handle_info(#'basic.consume_ok'{} = C, State) ->
	io:format("Consume: ~p ~n", [C]),
    {noreply, State};

handle_info(shutdown, State) ->
    {stop, normal, State};

handle_info(#'basic.cancel_ok'{}, State) ->
    {stop, normal, State};

handle_info(_Info, State) ->
	io:format("Info: ~p~n", [_Info]),
    {noreply, State}.

terminate(_Reason, #state{channel = Channel, consumer_tag = Tag,
	connection = Connection}) ->
    amqp_channel:call(Channel,#'basic.cancel'{consumer_tag = Tag}),
	amqp_connection:close(Connection),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
