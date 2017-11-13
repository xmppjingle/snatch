-module(claws_rest_tests).

-export([handle/2, handle_event/3]).

-behaviour(elli_handler).

-define(PORT, 8888).

-include_lib("eunit/include/eunit.hrl").
-include("snatch.hrl").

handle(Req, _Args) ->
    %% Delegate to our handler function
    handle(elli_request:method(Req), elli_request:path(Req), Req).

handle('GET',[<<"hello">>, <<"world">>], _Req) ->
    %% Reply with a normal response. 'ok' can be used instead of '200'
    %% to signal success.
    {ok, [], <<"Hello World!">>};

handle(_, _, _Req) ->
    {404, [], <<"Not Found">>}.

%% @doc: Handle request events, like request completed, exception
%% thrown, client timeout, etc. Must return 'ok'.
handle_event(_Event, _Data, _Args) ->
    ok.


startup() ->
    {ok, _} = application:ensure_all_started(snatch),
    {ok, PID} = elli:start_link([{callback, ?MODULE}, {port, ?PORT}]),
    Params = #{
        domain => "localhost",
        port => ?PORT,
        schema => "http"
    },
    {ok, _} = claws_rest:start_link(Params),
    {ok, PID}.

teardown(PID) ->
    ok = elli:stop(PID),
    ok = claws_rest:stop(),
    ok = snatch:stop(),
    ok = application:stop(snatch),
    ok = application:unload(snatch),
    ok.

request_200_test() ->
    {ok, PID} = startup(),
    {ok, _} = snatch:start_link(claws_rest, self()),
    ok = claws_rest:request("/hello/world"),
    Data = receive A -> A end,
    Response = #{body => "Hello World!",
                 code => "200",
                 headers => [{"Connection", "Keep-Alive"},
                             {"Content-Length", "12"}]},
    Via = #via{claws = claws_rest},
    ?assertMatch({received, Response, Via}, Data),
    ok = teardown(PID),
    ok.

request_404_test() ->
    {ok, PID} = startup(),
    {ok, _} = snatch:start_link(claws_rest, self()),
    ok = claws_rest:request("/"),
    Data = receive A -> A end,
    Response = #{body => "Not Found",
                 code => "404",
                 headers => [{"Connection", "Keep-Alive"},
                             {"Content-Length", "9"}]},
    Via = #via{claws = claws_rest},
    ?assertMatch({received, Response, Via}, Data),
    ok = teardown(PID),
    ok.
