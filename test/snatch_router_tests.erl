-module(snatch_router_tests).
-compile([warnings_as_errors, debug_info]).

-include_lib("eunit/include/eunit.hrl").

%% init/1 tests

init_with_pid_test() ->
    ?assertEqual({ok, self()}, snatch_router:init([self()])).

init_with_registered_name_test() ->
    register(snatch_router_test_proc, self()),
    {ok, PID} = snatch_router:init([snatch_router_test_proc]),
    ?assertEqual(self(), PID),
    unregister(snatch_router_test_proc).

init_with_undefined_test() ->
    ?assertError(badarg, snatch_router:init([undefined])).

%% handle_info/2 tests

handle_info_with_pid_test() ->
    {ok, PID} = snatch_router:init([self()]),
    ?assertEqual({noreply, PID},
                 snatch_router:handle_info({received, <<"hello">>}, PID)),
    receive
        {received, <<"hello">>} -> ok
    after 1000 -> throw(timeout)
    end.

handle_info_with_registered_name_test() ->
    register(snatch_router_test_name, self()),
    Result = snatch_router:handle_info(test_msg, snatch_router_test_name),
    ?assertEqual({noreply, snatch_router_test_name}, Result),
    receive
        test_msg -> ok
    after 1000 -> throw(timeout)
    end,
    unregister(snatch_router_test_name).

handle_info_with_unregistered_name_test() ->
    %% Should not crash when name is not registered
    ?assertEqual({noreply, nonexistent_proc},
                 snatch_router:handle_info(test_msg, nonexistent_proc)).

%% terminate/2 tests

terminate_test() ->
    ?assertEqual(ok, snatch_router:terminate(normal, self())).
