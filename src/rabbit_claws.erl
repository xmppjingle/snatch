-module(rabbit_claws).
-behaviour(gen_server).
-behaviour(claws).

-export([start_link/1, register/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([send/2, send/3, publish/1, publish/2]).

-include("amqp_client.hrl").
-include_lib("xmpp.hrl").
-include("snatch.hrl").
-include("rabbit_claws.hrl").

start_link(Params) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).

register(SocketConnection) ->
	gen_server:call(?MODULE, {register, SocketConnection}).

init(#{jid := JID, listener := Listener, host := Host} = Opts) ->
	State = 
		case amqp_connection:start(#amqp_params_network{host = Host, username = maps:get(username, Opts, <<"guest">>), password = maps:get(password, Opts, <<"guest">>)}) of
			{ok, Connection} ->
				case amqp_connection:open_channel(Connection) of
					{ok, Channel} ->						
						create_bind_queues(#state{jid = JID, channel = Channel, connection = Connection, listener = Listener, opts = Opts});
					_E ->
						lager:info("Could Not Open RabbitMQ Channel: ~p~n", [_E]),
						#state{}
				end;			
			_E -> 
				lager:info("Could Not Start RabbitMQ Connection: ~p~n", [_E]),
				#state{}
		end,	
	{ok, State}.

create_bind_queues(#state{channel = Channel, jid = JID, listener = Listener} = S) ->
	BareJID = snatch:to_bare(JID),
	
	#'exchange.declare_ok'{} = amqp_channel:call(Channel, #'exchange.declare'{exchange = ?EXCHANGE_DIRECT, type = ?DIRECT}),
	#'exchange.declare_ok'{} = amqp_channel:call(Channel, #'exchange.declare'{exchange = ?EXCHANGE_FANOUT, type = ?FANOUT}),

	{DirectQueue, _}= declare_bind_and_consume(Channel, <<?DIRECT/binary, ":", JID/binary>>, ?EXCHANGE_DIRECT, [JID, BareJID], whereis(?MODULE)),
	{EventQueue, _}	= declare_bind_and_consume(Channel, <<?FANOUT/binary, ":", JID/binary>>, ?EXCHANGE_FANOUT, [JID, BareJID], whereis(?MODULE)),

	snatch:forward(Listener, {connected, ?MODULE}),

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

handle_cast({send, Data, JID, ID}, State) ->
	lager:debug("Sending Message[~p]{~p}: ~p~n", [JID, ID, Data]),
	amqp_channel:cast(State#state.channel, #'basic.publish'{exchange = ?EXCHANGE_DIRECT,  routing_key = JID}, #amqp_msg{props = #'P_basic'{correlation_id = ID}, payload = Data}),
    {noreply, State};

handle_cast({publish, Data, JID}, State) ->
	lager:debug("Publishing Message[~p]: ~p~n", [JID, Data]),
	amqp_channel:cast(State#state.channel, #'basic.publish'{exchange = ?EXCHANGE_FANOUT,  routing_key = JID}, #amqp_msg{props = #'P_basic'{}, payload = Data}),
	{noreply, State};

handle_cast({publish, Data}, State) ->
	lager:debug("Publishing Message: ~p~n", [Data]),
	amqp_channel:cast(State#state.channel, #'basic.publish'{exchange = ?EXCHANGE_FANOUT}, #amqp_msg{props = #'P_basic'{}, payload = Data}),
	{noreply, State};

handle_cast(_Msg, State) ->	
    {noreply, State}.

handle_info({#'basic.deliver'{delivery_tag = Tag, exchange = Exchange, routing_key = Key}, #amqp_msg{props = #'P_basic'{correlation_id = ID}, payload = Payload}}, #state{listener = Listener} = State) ->
	lager:debug("Deliver[~p]{~p}: ~p~n via: ~p~n", [Key, ID, Payload, Exchange]),
	snatch:forward(Listener, {received, Payload, #via{jid = Key, exchange = Exchange, claws = ?MODULE}}),
	amqp_channel:cast(State#state.channel, #'basic.ack'{delivery_tag = Tag}),
	{noreply, State};

handle_info({#'basic.deliver'{delivery_tag = Tag, exchange = Exchange, routing_key = Key}, Message}, #state{listener = Listener} = State) ->
	lager:debug("Deliver[~p]: ~p~n via: ~p~n", [Key, Message#amqp_msg.payload, Exchange]),
	snatch:forward(Listener, {received, Message#amqp_msg.payload, #via{jid = Key, exchange = Exchange, claws = ?MODULE}}),
	amqp_channel:cast(State#state.channel, #'basic.ack'{delivery_tag = Tag}),
	{noreply, State};
		
handle_info(#'basic.consume_ok'{} = C, State) ->
	lager:debug("Consume: ~p ~n", [C]),
    {noreply, State};

handle_info({'DOWN', _ConnectionRef, process, _Connection, Reason}, #state{opts = Opts} = State) ->
    lager:info("AMQP connection error", []),
    terminate(Reason, State),
    NewState = 
    	case init(Opts) of
    		{ok, SState} ->
    			SState;
    		_ ->
    			State
    	end,
    {noreply, NewState};

handle_info(#'basic.cancel_ok'{}, State) ->
    {noreply, normal, State};

handle_info(shutdown, State) ->
    {stop, normal, State};

handle_info(_Info, State) ->
	lager:debug("Info: ~p~n", [_Info]),
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