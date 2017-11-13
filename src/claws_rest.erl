-module(claws_rest).

-behaviour(gen_server).

-include_lib("ibrowse/include/ibrowse.hrl").
-include("snatch.hrl").

-export([start_link/1,
         stop/0,
         request/1,
         request/2,
         request/3,
         request/4]).
-export([init/1,
         handle_info/2,
         handle_cast/2,
         handle_call/3,
         code_change/3,
         terminate/2]).

-define(DEFAULT_SCHEMA, "http").
-define(DEFAULT_MAX_SESSIONS, 10).
-define(DEFAULT_PIPELINE_SIZE, 1).
-define(DEFAULT_PORT, 80).

-record(ibrowse_async_headers, {id, code, headers}).
-record(ibrowse_async_response, {id, body}).
-record(ibrowse_async_response_end, {id}).

start_link(Params) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).

stop() ->
    gen_server:stop(?MODULE).

request(URI) ->
    gen_server:cast(?MODULE, {request, get, URI, [], <<>>}).

request(Method, URI) ->
    gen_server:cast(?MODULE, {request, Method, URI, [], <<>>}).

request(Method, URI, Headers) ->
    gen_server:cast(?MODULE, {request, Method, URI, Headers, <<>>}).

request(Method, URI, Headers, Body) ->
    gen_server:cast(?MODULE, {request, Method, URI, Headers, Body}).

init(#{ domain := Domain } = Opts) ->
    Schema = maps:get(schema, Opts, ?DEFAULT_SCHEMA),
    MaxSessions = maps:get(max_sessions, Opts, ?DEFAULT_MAX_SESSIONS),
    MaxPipelineSize = maps:get(max_pipeline_size, Opts, ?DEFAULT_PIPELINE_SIZE),
    Port = maps:get(port, Opts, ?DEFAULT_PORT),
    ibrowse:set_dest(Domain, Port, [{max_sessions, MaxSessions},
                                    {max_pipeline_size, MaxPipelineSize}]),
    {ok, Opts#{schema => Schema,
               max_sessions => MaxSessions,
               max_pipeline_size => MaxPipelineSize,
               port => Port,
               responses => orddict:new()}}.

handle_info(#ibrowse_async_headers{id = ID} = Headers, Opts) ->
    NewOpts = add_data(ID, Headers, Opts),
    {noreply, NewOpts};

handle_info(#ibrowse_async_response{id = ID} = Body, Opts) ->
    NewOpts = add_data(ID, Body, Opts),
    {noreply, NewOpts};

handle_info(#ibrowse_async_response_end{id = ID}, Opts) ->
    {Data, NewOpts} = pop_data(ID, Opts),
    snatch:received(Data, #via{claws = ?MODULE}),
    {noreply, NewOpts}.

handle_cast({request, Method, URI, Headers, Body},
            #{schema := Schema, domain := Domain, port := Port} = Opts) ->
    URL = Schema ++ "://" ++ Domain ++ ":" ++ integer_to_list(Port) ++ URI,
    HttpOpts = [{stream_to, ?MODULE}],
    {ibrowse_req_id, _ID} = ibrowse:send_req(URL, Headers, Method, Body,
                                             HttpOpts),
    {noreply, Opts};

handle_cast(_Msg, Opts) ->
    {noreply, Opts}.

handle_call(_Msg, _From, Opts) ->
    {reply, ignored, Opts}.

code_change(_OldVsn, Opts, _Extra) ->
    Schema = maps:get(schema, Opts, ?DEFAULT_SCHEMA),
    MaxSessions = maps:get(max_sessions, Opts, ?DEFAULT_MAX_SESSIONS),
    MaxPipelineSize = maps:get(max_pipeline_size, Opts, ?DEFAULT_PIPELINE_SIZE),
    Port = maps:get(port, Opts, ?DEFAULT_PORT),
    io:format("updated opts!~n", []),
    {ok, Opts#{ schema => Schema,
                max_sessions => MaxSessions,
                max_pipeline_size => MaxPipelineSize,
                port => Port }}.

terminate(_Reason, _State) ->
    ok.

add_data(ID, #ibrowse_async_headers{code = Code, headers = Headers},
         #{responses := Responses} = Opts) ->
    NewResponses = orddict:update(ID, fun(Data) ->
        Data#{code => Code, headers => Headers}
    end, #{code => Code, headers => Headers}, Responses),
    Opts#{responses => NewResponses};

add_data(ID, #ibrowse_async_response{body = Body},
         #{responses := Responses} = Opts) ->
    NewResponses = orddict:update(ID, fun
        (#{body := OldBody} = Data) ->
            Data#{body => <<OldBody/binary, Body/binary>>};
        (#{} = Data) ->
            Data#{body => Body}
    end, #{body => Body}, Responses),
    Opts#{responses => NewResponses}.

pop_data(ID, #{responses := Responses} = Opts) ->
    Value = orddict:fetch(ID, Responses),
    NewResponses = orddict:erase(ID, Responses),
    {Value, Opts#{responses => NewResponses}}.
