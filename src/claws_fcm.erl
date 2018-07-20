%%%-------------------------------------------------------------------
%%% @author yan.guiborat
%%% @copyright (C) 2018
%%% @doc
%%%
%%% @end
%%% Created : 08. févr. 2018 10:54
%%%-------------------------------------------------------------------
-module(claws_fcm).
-author("yan.guiborat").

-behaviour(gen_server).

%% API
-include_lib("ibrowse/include/ibrowse.hrl").
-include("snatch.hrl").

-export([start_link/0, start_link/1,
  stop/0]).

-export([init/1,
  handle_info/2,
  handle_cast/2,
  handle_call/3,
  code_change/3,
  terminate/2]).

-export([new_connection/3, send/2, close_connections/1]).

-define(SERVER, ?MODULE).

-record(state, {
  poolpid :: pid() | undefined,
  watchers = #{} :: map(),
  connections_status = #{},
  connections
  }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

start_link(FcmConfig) ->
  error_logger:info_msg("starting new connection to FCM :~p",[FcmConfig]),
  gen_server:start_link({local, ?SERVER}, ?MODULE, FcmConfig, []).


stop() ->
  gen_server:stop(?MODULE).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  %% Start the push queue with rate control
  {ok, #state{connections = dict:new()}};

init([#{gcs_add := FcmAdd, gcs_port := FcmPort, connections := Connections}]) ->
  error_logger:info_msg("Initialising new connections to FCM :~p",[{FcmPort, FcmAdd, Connections}]),

  %% Start the push queue with rate control
  AppIdIndexedCons = lists:foldl(
    fun(Connection, Acc) ->
      error_logger:info_msg("Initialising  connection  :~p",[Connection]),
      {ServerId, ServerKey, PoolSize, AppIds} = Connection,

      %%con_name := ConName, gcs_add := Gcs_add, gcs_port := Gcs_Port, server_id := ServerId, server_key := ServerKey}
      case new_connection(PoolSize, ServerId, #{app_ids => AppIds, gcs_add => FcmAdd, gcs_port => FcmPort, server_id => ServerId, server_key => ServerKey}) of
        error ->
          ok;
        {_, PoolName} ->
          lists:foldl(
            fun(AppId) ->
              dict:store(AppId, PoolName, Acc)
            end,
            #{},
            AppIds
          )
      end
    end,
    #{},
    Connections
  ),
  {ok, #state{connections = AppIdIndexedCons}}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call({new_connection, PoolSize, ConnectionName, FcmConfig}, _From, State) ->
  %%jobs:add_queue(PoolName,[{regulators, [{ rate, [{limit, 10000}]}]}]),
  error_logger:info_msg("Creating new connection to FCM :~p",[{ConnectionName, FcmConfig}]),

  case maps:get(ConnectionName, State#state.connections_status, undefined) of
    undefined ->
      %% Pooler takes only atoms as poolname ...
      PoolName = case ConnectionName of
                   Binary when is_binary(Binary) ->
                     binary_to_atom(ConnectionName, latin1);
                   Else when is_atom(Else)-> Else
                 end,

      UpdatedFcmConf = maps:put(con_name, ConnectionName, FcmConfig),

      %% start a pool of process to consume from the push queue
      PoolSpec = [
        {name, PoolName},
        {worker_module, claws_fcm_worker},
        {size, PoolSize},
        {max_overflow, 10},
        {max_count, 10},
        {init_count, 2},
        {strategy, lifo},
        {start_mfa, {claws_fcm_worker, start_link, [UpdatedFcmConf]}},
        {fcm_conf, UpdatedFcmConf}
      ],

      {ok, P} = try pooler:new_pool(PoolSpec) of
                  Pp  ->
                    Pp
                catch
                  M:E ->
                    error_logger:error_msg("Error when creating pool :~p",[{M,E}])
                end,

      error_logger:info_msg("Pool creation result ~p",[P]),


      NewConList = lists:foldl(
        fun(AppId, Dict) ->
          dict:store(AppId, PoolName, Dict) end,
        State#state.connections, maps:get(app_ids, FcmConfig)

      ),

      error_logger:info_msg("New Con List ~p",[NewConList]),


      {reply, {ConnectionName, PoolName, P},
        State#state{connections = NewConList}};

    _ ->
      error_logger:info_msg("Connection ~p is already openned :~p ",[ConnectionName]),

      {reply, already_openned, State}
  end;




handle_call({send, Data, AppId}, _From, State) ->
  error_logger:info_msg("Fetching connection for appid :~p ",[AppId, State#state.connections]),
  try dict:fetch(AppId,State#state.connections) of
    Connection ->
          P = pooler:take_member(Connection),
          error_logger:info_msg("Pool member :~p",[P]),
          gen_statem:cast(P, {send, Data}),
          pooler:return_member(Connection, P, ok),
          {reply, ok, State}
    catch
        M:E ->
          error_logger:info_msg("Error when fetching connection for appid :~p ",[{M,E}]),
          {reply, ok, State}
  end;



handle_call({close_connection, ConnectionName}, _From, State) ->
  case maps:get(ConnectionName,State#state.connections_status, undefined) of
    {_State, PoolName, _P, _Workers} ->
      pooler:rm_pool(PoolName),
      {reply, ok, State#state{connections_status = maps:remove(ConnectionName,State#state.connections_status)}};
    undefined ->
      error_logger:info_msg("Can't close connection ~p as it doesnt exists.",[ConnectionName]),
      {reply, ok, State}
  end;


handle_call(Message, From, State) ->
  error_logger:warning_msg("Unmanaged message from ~p at claw FCM : ~p",[From,Message]),
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).


handle_info({ready, ConName, Pid}, State) ->
  error_logger:info_msg("Connection Process is readty :~p    ~p",[ConName, Pid]),
  ConnectionsStatus = State#state.connections_status,
  {_Status, PoolName, P, Workers} = maps:get(ConName, ConnectionsStatus, []),
  case lists:delete(Pid, Workers) of
          [] ->
            error_logger:info_msg("All workers ready. Notifying : ~p",[State#state.watchers]),
            lists:foreach(
              fun(PidWatcher) ->
                PidWatcher!{connection_ready, ConName} end, maps:get(ConName, State#state.watchers,[])
            ),
            {noreply,State#state{connections_status = maps:put(ConName,{ready, PoolName, P, []},ConnectionsStatus)}};

          NewListOfWorkers ->
            error_logger:info_msg("New Worker List :~p   ~p",[ConName, NewListOfWorkers]),
            {noreply,State#state{connections_status = maps:put(ConName,{connecting, PoolName, P, NewListOfWorkers}, ConnectionsStatus)}}
  end;


handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------

-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


send(Data, ConnectionName) ->
  gen_server:call(?SERVER, {send, Data, ConnectionName}).


close_connections(ConnectionName) ->
  gen_server:call(?SERVER, {close_connection, ConnectionName}).



%%%===================================================================
%%% Internal functions
%%%===================================================================


new_connection(PoolSize, ConnectionName, FcmConfig) ->
  %%jobs:add_queue(PoolName,[{regulators, [{ rate, [{limit, 10000}]}]}]),
  error_logger:info_msg("Creating new connection to FCM :~p",[{ConnectionName, FcmConfig}]),


  UpdatedFcmConf = maps:put(con_name, ConnectionName, FcmConfig),

  %% start a pool of process to consume from the push queue
  PoolSpec = [
    {name, ConnectionName},
    {worker_module, claws_fcm_worker},
    {size, PoolSize},
    {max_overflow, 10},
    {max_count, 10},
    {init_count, 2},
    {strategy, lifo},
    {start_mfa, {claws_fcm_worker, start_link, [UpdatedFcmConf]}},
    {fcm_conf, UpdatedFcmConf}
  ],

  try pooler:new_pool(PoolSpec) of
    Pp  ->
      error_logger:info_msg("Pool creation result ~p",[Pp]),
      {Pp, ConnectionName}

  catch
    M:E ->
      error_logger:error_msg("Error when creating pool :~p",[{M,E}])
  end.



%% Data is :
%% {list, To, Payload}} : where To is the Token where the push will be sent and Payload is a key-value list matching
%% json fields to send over FCM.
%%
%% Ex: [{<<"data">>, <<"Some data">>}, {<<"notification">>,#{<<"title">> => TitleVal, <<"body">> => BodyVal}}]
%% The To parameter is added to the payload by the claw.
%%
%% Data can also be :
%%
%% {json_map, Payload}} : In this case, Payload is a map that will be converted to JSON before being sent to google FCM
%% The token is supposed to be already stored inside the map under the key : "to".
%%
%%
%%


%%deprecated
%%-spec(send(Data :: tuple()) -> tuple()).
%%send(Data) ->
%%  jobs:run(push_queue,fun()->
%%                            P = pooler:take_member(push_pool),
%%                            gen_statem:cast(P, {send, Data}),
%%                            pooler:return_member(push_pool, P, ok)
%%                         end).
%%
