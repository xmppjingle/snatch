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

-export([start_link/0,
  stop/0]).

-export([init/1,
  handle_info/2,
  handle_cast/2,
  handle_call/3,
  code_change/3,
  terminate/2]).

-export([new_connection/3, send/1, send/2]).

-define(SERVER, ?MODULE).

-record(state, {
  poolpid :: pid() | undefined
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
  application:start(pooler),
  application:start(fxml),
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).



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
init(_) ->
  %% Start the push queue with rate control
  application:start(jobs),
  {ok, #state{}}.

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
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

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

%%%===================================================================
%%% Internal functions
%%%===================================================================

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
%% Ex :
%%



new_connection(PoolSize, PoolName, FcmConfig) ->
  %%jobs:add_queue(PoolName,[{regulators, [{ rate, [{limit, 10000}]}]}]),

  %% start a pool of process to consume from the push queue
  PoolSpec = [
    {name, PoolName},
    {worker_module, claws_fcm_worker},
    {size, PoolSize},
    {max_overflow, 10},
    {max_count, 10},
    {init_count, 2},
    {strategy, lifo},
    {start_mfa, {claws_fcm_worker, start_link, [FcmConfig]}},
    {fcm_conf, FcmConfig}
  ],
  pooler:new_pool(PoolSpec).


send(Data, PoolName) ->
    P = pooler:take_member(PoolName),
    gen_statem:cast(P, {send, Data}),
    pooler:return_member(push_pool, P, ok).


%%deprecated
-spec(send(Data :: tuple()) -> tuple()).
send(Data) ->
  jobs:run(push_queue,fun()->
                            P = pooler:take_member(push_pool),
                            gen_statem:cast(P, {send, Data}),
                            pooler:return_member(push_pool, P, ok)
                         end).

