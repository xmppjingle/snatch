-module(snatch_xml_tests).
-compile([warnings_as_errors, debug_info]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("fast_xml/include/fxml.hrl").

%% clean_spaces/1 tests

clean_spaces_no_children_test() ->
    El = #xmlel{name = <<"tag">>, attrs = [], children = []},
    ?assertEqual(El, snatch_xml:clean_spaces(El)).

clean_spaces_removes_whitespace_cdata_test() ->
    El = #xmlel{name = <<"tag">>, attrs = [],
                children = [{xmlcdata, <<"  ">>},
                            {xmlcdata, <<"hello">>}]},
    Expected = #xmlel{name = <<"tag">>, attrs = [],
                      children = [{xmlcdata, <<"hello">>}]},
    ?assertEqual(Expected, snatch_xml:clean_spaces(El)).

clean_spaces_recursive_test() ->
    Inner = #xmlel{name = <<"inner">>, attrs = [],
                   children = [{xmlcdata, <<"\n\t">>},
                               {xmlcdata, <<"data">>}]},
    El = #xmlel{name = <<"outer">>, attrs = [], children = [Inner]},
    Result = snatch_xml:clean_spaces(El),
    [CleanedInner] = Result#xmlel.children,
    ?assertEqual([{xmlcdata, <<"data">>}], CleanedInner#xmlel.children).

%% get_cdata/1 tests

get_cdata_single_test() ->
    El = #xmlel{name = <<"body">>, attrs = [],
                children = [{xmlcdata, <<"hello">>}]},
    ?assertEqual(<<"hello">>, snatch_xml:get_cdata(El)).

get_cdata_multiple_test() ->
    El = #xmlel{name = <<"body">>, attrs = [],
                children = [{xmlcdata, <<"hello ">>},
                            {xmlcdata, <<"world">>}]},
    ?assertEqual(<<"hello world">>, snatch_xml:get_cdata(El)).

get_cdata_empty_test() ->
    El = #xmlel{name = <<"body">>, attrs = [], children = []},
    ?assertEqual(<<>>, snatch_xml:get_cdata(El)).

get_cdata_nested_test() ->
    Inner = #xmlel{name = <<"span">>, attrs = [],
                   children = [{xmlcdata, <<"nested">>}]},
    El = #xmlel{name = <<"body">>, attrs = [],
                children = [{xmlcdata, <<"before ">>}, Inner]},
    ?assertEqual(<<"before nested">>, snatch_xml:get_cdata(El)).

get_cdata_skip_empty_child_test() ->
    Inner = #xmlel{name = <<"br">>, attrs = [], children = []},
    El = #xmlel{name = <<"body">>, attrs = [],
                children = [Inner, {xmlcdata, <<"text">>}]},
    ?assertEqual(<<"text">>, snatch_xml:get_cdata(El)).

%% get_attr/2 and get_attr/3 tests

get_attr_found_test() ->
    El = #xmlel{name = <<"iq">>,
                attrs = [{<<"type">>, <<"get">>}, {<<"id">>, <<"1">>}],
                children = []},
    ?assertEqual(<<"get">>, snatch_xml:get_attr(<<"type">>, El)).

get_attr_not_found_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [], children = []},
    ?assertEqual(undefined, snatch_xml:get_attr(<<"type">>, El)).

get_attr_with_default_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [], children = []},
    ?assertEqual(<<"chat">>, snatch_xml:get_attr(<<"type">>, El, <<"chat">>)).

get_attr_found_ignores_default_test() ->
    El = #xmlel{name = <<"iq">>,
                attrs = [{<<"type">>, <<"get">>}],
                children = []},
    ?assertEqual(<<"get">>, snatch_xml:get_attr(<<"type">>, El, <<"chat">>)).

%% get_attr_atom/2 and get_attr_atom/3 tests

get_attr_atom_found_test() ->
    El = #xmlel{name = <<"el">>,
                attrs = [{<<"type">>, <<"chat">>}],
                children = []},
    ?assertEqual(chat, snatch_xml:get_attr_atom(<<"type">>, El)).

get_attr_atom_not_found_test() ->
    El = #xmlel{name = <<"el">>, attrs = [], children = []},
    ?assertEqual(undefined, snatch_xml:get_attr_atom(<<"type">>, El)).

get_attr_atom_with_default_test() ->
    El = #xmlel{name = <<"el">>, attrs = [], children = []},
    ?assertEqual(normal, snatch_xml:get_attr_atom(<<"type">>, El, normal)).

%% get_attr_int/3 tests

get_attr_int_found_test() ->
    El = #xmlel{name = <<"el">>,
                attrs = [{<<"code">>, <<"404">>}],
                children = []},
    ?assertEqual(404, snatch_xml:get_attr_int(<<"code">>, El, 0)).

get_attr_int_not_found_test() ->
    El = #xmlel{name = <<"el">>, attrs = [], children = []},
    ?assertEqual(0, snatch_xml:get_attr_int(<<"code">>, El, 0)).
