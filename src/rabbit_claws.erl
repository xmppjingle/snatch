-module(rabbit_claws).
-behaviour(gen_server).
-behaviour(claws).

-export([start_link/1, register/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([send/2, publish/1]).

-include("amqp_client.hrl").
-include_lib("xmpp.hrl").

-record(state, {jid, channel, connection, direct_queue, fanout_queue, listener}).

-define(EXCHANGE_DIRECT, <<"xmpp_direct">>).
-define(EXCHANGE_FANOUT, <<"xmpp_fanout">>).
-define(DIRECT, <<"direct">>).
-define(FANOUT, <<"fanout">>).

start_link(Params) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).

register(SocketConnection) ->
	gen_server:call(?MODULE, {register, SocketConnection}).

init(#{jid := JID, listener := Listener}) ->
	State = 
		case amqp_connection:start(#amqp_params_network{}) of
			{ok, Connection} ->
				case amqp_connection:open_channel(Connection) of
					{ok, Channel} ->
						create_bind_queues(#state{jid = JID, channel = Channel, connection = Connection, listener = Listener});
					_E ->
						lager:info("Could Not Open RabbitMQ Channel: ~p~n", [_E]),
						#state{}
				end;			
			_E -> 
				lager:info("Could Not Start RabbitMQ Connection: ~p~n", [_E]),
				#state{}
		end,
	{ok, State}.

create_bind_queues(#state{channel = Channel, jid = JID} = S) ->
	BareJID = snatch:to_bare(JID),
	
	#'exchange.declare_ok'{} = amqp_channel:call(Channel, #'exchange.declare'{exchange = ?EXCHANGE_DIRECT, type = ?DIRECT}),
	#'exchange.declare_ok'{} = amqp_channel:call(Channel, #'exchange.declare'{exchange = ?EXCHANGE_FANOUT, type = ?FANOUT}),

	{DirectQueue, _}= declare_bind_and_consume(Channel, <<?DIRECT/binary, ":", JID/binary>>, ?EXCHANGE_DIRECT, [JID, BareJID], whereis(?MODULE)),
	{EventQueue, _}	= declare_bind_and_consume(Channel, <<?FANOUT/binary, ":", JID/binary>>, ?EXCHANGE_FANOUT, [JID, BareJID], whereis(?MODULE)),

	S#state{direct_queue = DirectQueue, fanout_queue = EventQueue}.

declare_bind_and_consume(Channel, Name, Exchange, Routes, Listener) ->
	#'queue.declare_ok'{queue = Queue} = amqp_channel:call(Channel, #'queue.declare'{queue = Name}),
	[ #'queue.bind_ok'{} = amqp_channel:call(Channel, #'queue.bind'{queue = Queue, exchange = Exchange, routing_key = R}) || R <- Routes],
	#'basic.consume_ok'{consumer_tag = Tag} = amqp_channel:subscribe(Channel, #'basic.consume'{queue = Queue}, Listener),
	{Queue, Tag}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({send, Data, JID}, State) ->
	lager:debug("Sending Message[~p]: ~p~n", [JID, Data]),
	amqp_channel:cast(State#state.channel, #'basic.publish'{exchange = ?EXCHANGE_DIRECT,  routing_key = JID}, #amqp_msg{props = #'P_basic'{}, payload = Data}),
    {noreply, State};

handle_cast({publish, Data}, State) ->
	lager:debug("Publishing Message[~p]: ~p~n", [Data]),
	amqp_channel:cast(State#state.channel, #'basic.publish'{exchange = ?EXCHANGE_FANOUT}, #amqp_msg{props = #'P_basic'{}, payload = Data}),
	{noreply, State};

handle_cast(_Msg, State) ->	
    {noreply, State}.

handle_info({#'basic.deliver'{delivery_tag = Tag}, Message}, #state{listener = Listener} = State) ->
	lager:debug("Deliver: ~p~n", [Message#amqp_msg.payload]),
	snatch:forward(Listener, {received, Message#amqp_msg.payload}),
	amqp_channel:cast(State#state.channel, #'basic.ack'{delivery_tag = Tag}),
	{noreply, State};
		
handle_info(#'basic.consume_ok'{} = C, State) ->
	lager:debug("Consume: ~p ~n", [C]),
    {noreply, State};

handle_info(shutdown, State) ->
    {stop, normal, State};

handle_info(#'basic.cancel_ok'{}, State) ->
    {stop, normal, State};

handle_info(_Info, State) ->
	lager:debug("Info: ~p~n", [_Info]),
    {noreply, State}.

terminate(_Reason, #state{channel = Channel, connection = Connection}) ->
    amqp_channel:call(Channel,#'basic.cancel'{}),
	amqp_connection:close(Connection),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

send(Data, JID) ->
	gen_server:cast(?MODULE, {send, Data, JID}).

publish(Data) ->
	gen_server:cast(?MODULE, {publish, Data}).