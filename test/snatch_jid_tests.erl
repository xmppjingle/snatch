-module(snatch_jid_tests).
-compile([warnings_as_errors, debug_info]).

-include_lib("eunit/include/eunit.hrl").

%% is_full/1 tests

is_full_with_resource_test() ->
    ?assert(snatch_jid:is_full(<<"user@domain.com/resource">>)).

is_full_without_resource_test() ->
    ?assertNot(snatch_jid:is_full(<<"user@domain.com">>)).

is_full_bare_domain_test() ->
    ?assertNot(snatch_jid:is_full(<<"domain.com">>)).

is_full_domain_with_resource_test() ->
    ?assert(snatch_jid:is_full(<<"domain.com/resource">>)).

is_full_empty_string_test() ->
    ?assertNot(snatch_jid:is_full(<<>>)).

%% to_bare/1 tests

to_bare_full_jid_test() ->
    ?assertEqual(<<"user@domain.com">>,
                 snatch_jid:to_bare(<<"user@domain.com/resource">>)).

to_bare_already_bare_test() ->
    ?assertEqual(<<"user@domain.com">>,
                 snatch_jid:to_bare(<<"user@domain.com">>)).

to_bare_domain_only_test() ->
    ?assertEqual(<<"domain.com">>,
                 snatch_jid:to_bare(<<"domain.com">>)).

to_bare_domain_with_resource_test() ->
    ?assertEqual(<<"domain.com">>,
                 snatch_jid:to_bare(<<"domain.com/resource">>)).

to_bare_resource_with_slash_test() ->
    %% re:split splits on first slash only (returns 2 parts)
    ?assertEqual(<<"user@domain.com">>,
                 snatch_jid:to_bare(<<"user@domain.com/res">>)).
