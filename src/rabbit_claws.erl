-module(rabbit_claws).
-behaviour(gen_server).

-export([start_link/1, publish/1, register/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("amqp_client.hrl").
-include_lib("xmpp.hrl").

-record(state, {jid, channel, connection, direct_queue, any_queue, event_queue}).

-define(EXCHANGE_IQ, <<"iq">>).
-define(EXCHANGE_PRESENCE, <<"presence">>).

-define(DIRECT, <<"direct">>).
-define(BROADCAST, <<"fanout">>).

start_link(Params) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).

publish(Message) ->
	gen_server:call(?MODULE, {publish, Message}).

register(SocketConnection) ->
	gen_server:call(?MODULE, {register, SocketConnection}).

init([JID]) ->
	{ok, Connection} = amqp_connection:start(#amqp_params_network{}),
	{ok, Channel} = amqp_connection:open_channel(Connection),
	State = create_bind_queues(#state{jid = JID, channel = Channel, connection = Connection}),
	{ok, create_bind_queues(State)}.

create_bind_queues(#state{channel = Channel, jid = JID} = S) ->
	BareJID = snatch:to_bare(JID),
	#'exchange.declare_ok'{} = amqp_channel:call(Channel, #'exchange.declare'{exchange = ?EXCHANGE_IQ, type = ?DIRECT}),
	#'exchange.declare_ok'{} = amqp_channel:call(Channel, #'exchange.declare'{exchange = ?EXCHANGE_PRESENCE, type = ?BROADCAST}),

	#'queue.declare_ok'{queue = DirectQueue} = amqp_channel:call(Channel, #'queue.declare'{queue = JID}),
	#'queue.declare_ok'{queue = AnyQueue} = amqp_channel:call(Channel, #'queue.declare'{queue = BareJID}),
	#'queue.declare_ok'{queue = EventQueue} = amqp_channel:call(Channel, #'queue.declare'{queue = BareJID}),

	#'queue.bind_ok'{} = amqp_channel:call(Channel,	#'queue.bind'{queue = DirectQueue, exchange = ?EXCHANGE_IQ}),
	#'queue.bind_ok'{} = amqp_channel:call(Channel,	#'queue.bind'{queue = AnyQueue, exchange = ?EXCHANGE_IQ}),
	#'queue.bind_ok'{} = amqp_channel:call(Channel,	#'queue.bind'{queue = EventQueue, exchange = ?EXCHANGE_PRESENCE}),
	#'queue.bind_ok'{} = amqp_channel:call(Channel,	#'queue.bind'{queue = EventQueue, exchange = ?EXCHANGE_PRESENCE}),
		
	#'basic.consume_ok'{consumer_tag = _} = amqp_channel:subscribe(Channel, #'basic.consume'{queue = DirectQueue}, whereis(?MODULE)),
	#'basic.consume_ok'{consumer_tag = _} = amqp_channel:subscribe(Channel, #'basic.consume'{queue = AnyQueue}, whereis(?MODULE)),
	#'basic.consume_ok'{consumer_tag = _} = amqp_channel:subscribe(Channel, #'basic.consume'{queue = EventQueue}, whereis(?MODULE)),
	
	S#state{direct_queue = DirectQueue, any_queue = AnyQueue, event_queue = EventQueue}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({publish, Message, Exchange},State) ->
	amqp_channel:cast(State#state.channel, #'basic.publish'{exchange = Exchange}, #amqp_msg{props = #'P_basic'{}, payload = Message}),
	{noreply, State};

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

terminate(_Reason, #state{channel = Channel, connection = Connection}) ->
    amqp_channel:call(Channel,#'basic.cancel'{}),
	amqp_connection:close(Connection),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
