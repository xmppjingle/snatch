-module(claws_xmpp_utils_tests).
-compile([warnings_as_errors, debug_info]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("fast_xml/include/fxml.hrl").
-include("claws_xmpp.hrl").

-define(FROM, <<"alice@example.com">>).
-define(TO, <<"bob@example.com">>).
-define(ID, <<"msg1">>).

%% iq/4 and iq/5 tests

iq_5_test() ->
    Result = claws_xmpp_utils:iq(<<"get">>, ?FROM, ?TO, ?ID, <<"<query/>">>),
    ?assertEqual(<<"<iq type='get' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'><query/></iq>">>, Result).

iq_4_test() ->
    Result = claws_xmpp_utils:iq(<<"get">>, ?TO, ?ID, <<"<query/>">>),
    ?assertEqual(<<"<iq type='get' to='bob@example.com' "
                   "id='msg1'><query/></iq>">>, Result).

%% empty_iq/3 and empty_iq/4 tests

empty_iq_4_test() ->
    Result = claws_xmpp_utils:empty_iq(<<"result">>, ?FROM, ?TO, ?ID),
    ?assertEqual(<<"<iq type='result' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'/>">>, Result).

empty_iq_3_test() ->
    Result = claws_xmpp_utils:empty_iq(<<"result">>, ?TO, ?ID),
    ?assertEqual(<<"<iq type='result' to='bob@example.com' "
                   "id='msg1'/>">>, Result).

%% iq_set/4 test

iq_set_test() ->
    Result = claws_xmpp_utils:iq_set(?FROM, ?TO, ?ID, <<"<query/>">>),
    ?assertEqual(<<"<iq type='set' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'><query/></iq>">>, Result).

%% iq_result tests

iq_result_3_test() ->
    Result = claws_xmpp_utils:iq_result(?FROM, ?TO, ?ID),
    ?assertEqual(<<"<iq type='result' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'/>">>, Result).

iq_result_record_test() ->
    IQ = #iq{from = ?FROM, to = ?TO, id = ?ID},
    Result = claws_xmpp_utils:iq_result(IQ),
    %% Note: result swaps from/to
    ?assertEqual(<<"<iq type='result' from='bob@example.com' "
                   "to='alice@example.com' id='msg1'/>">>, Result).

%% iq_error tests

iq_error_3_test() ->
    Result = claws_xmpp_utils:iq_error(?FROM, ?TO, ?ID),
    ?assertEqual(<<"<iq type='error' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'/>">>, Result).

iq_error_record_test() ->
    IQ = #iq{from = ?FROM, to = ?TO, id = ?ID},
    Result = claws_xmpp_utils:iq_error(IQ),
    ?assertEqual(<<"<iq type='error' from='bob@example.com' "
                   "to='alice@example.com' id='msg1'/>">>, Result).

%% message/5 test

message_test() ->
    Result = claws_xmpp_utils:message(<<"chat">>, ?FROM, ?TO, ?ID,
                                       <<"<body>hi</body>">>),
    ?assertEqual(<<"<message type='chat' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'>"
                   "<body>hi</body></message>">>, Result).

%% presence tests

presence_5_test() ->
    Result = claws_xmpp_utils:presence(<<"subscribe">>, ?FROM, ?TO, ?ID,
                                        <<"<status>hi</status>">>),
    ?assertEqual(<<"<presence type='subscribe' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'>"
                   "<status>hi</status></presence>">>, Result).

presence_4_test() ->
    Result = claws_xmpp_utils:presence(<<"subscribe">>, ?TO, ?ID,
                                        <<"<status/>">>),
    ?assertEqual(<<"<presence type='subscribe' to='bob@example.com' "
                   "id='msg1'><status/></presence>">>, Result).

empty_presence_4_test() ->
    Result = claws_xmpp_utils:empty_presence(<<"available">>, ?FROM, ?TO, ?ID),
    ?assertEqual(<<"<presence type='available' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'/>">>, Result).

empty_presence_3_test() ->
    Result = claws_xmpp_utils:empty_presence(<<"available">>, ?TO, ?ID),
    ?assertEqual(<<"<presence type='available' to='bob@example.com' "
                   "id='msg1'/>">>, Result).

empty_presence_2_test() ->
    Result = claws_xmpp_utils:empty_presence(<<"subscribe">>, ?TO),
    ?assertEqual(<<"<presence type='subscribe' "
                   "to='bob@example.com'/>">>, Result).

empty_presence_1_test() ->
    Result = claws_xmpp_utils:empty_presence(?TO),
    ?assertEqual(<<"<presence to='bob@example.com'/>">>, Result).

presence_available_3_test() ->
    Result = claws_xmpp_utils:presence_available(?FROM, ?TO, ?ID),
    ?assertEqual(<<"<presence type='available' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'/>">>, Result).

presence_available_4_test() ->
    Result = claws_xmpp_utils:presence_available(?FROM, ?TO, ?ID,
                                                  <<"<show>chat</show>">>),
    ?assertEqual(<<"<presence type='available' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'>"
                   "<show>chat</show></presence>">>, Result).

presence_unavailable_test() ->
    Result = claws_xmpp_utils:presence_unavailable(?FROM, ?TO, ?ID),
    ?assertEqual(<<"<presence type='unavailable' from='alice@example.com' "
                   "to='bob@example.com' id='msg1'/>">>, Result).

presence_subscribe_test() ->
    Result = claws_xmpp_utils:presence_subscribe(?TO),
    ?assertEqual(<<"<presence type='subscribe' "
                   "to='bob@example.com'/>">>, Result).

presence_subscribed_test() ->
    Result = claws_xmpp_utils:presence_subscribed(?TO),
    ?assertEqual(<<"<presence type='subscribed' "
                   "to='bob@example.com'/>">>, Result).

%% normalize_jid tests

normalize_jid_full_tuple_test() ->
    ?assertEqual(<<"user@domain.com/res">>,
                 claws_xmpp_utils:normalize_jid({<<"user">>, <<"domain.com">>,
                                                  <<"res">>})).

normalize_jid_bare_tuple_test() ->
    ?assertEqual(<<"user@domain.com">>,
                 claws_xmpp_utils:normalize_jid({<<"user">>, <<"domain.com">>,
                                                  undefined})).

normalize_jid_domain_only_test() ->
    ?assertEqual(<<"domain.com">>,
                 claws_xmpp_utils:normalize_jid({undefined, <<"domain.com">>,
                                                  undefined})).

normalize_jid_binary_test() ->
    ?assertEqual(<<"user@domain.com">>,
                 claws_xmpp_utils:normalize_jid(<<"user@domain.com">>)).

normalize_jid_list_test() ->
    ?assertEqual(<<"user@domain.com">>,
                 claws_xmpp_utils:normalize_jid("user@domain.com")).

%% get_name tests

get_name_xmlel_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [], children = []},
    ?assertEqual(<<"iq">>, claws_xmpp_utils:get_name(El)).

get_name_non_xmlel_test() ->
    ?assertEqual(<<>>, claws_xmpp_utils:get_name(something_else)).

%% get_children tests

get_children_1_test() ->
    Child = #xmlel{name = <<"query">>, attrs = [], children = []},
    El = #xmlel{name = <<"iq">>, attrs = [], children = [Child]},
    ?assertEqual([Child], claws_xmpp_utils:get_children(El)).

get_children_1_non_xmlel_test() ->
    ?assertEqual([], claws_xmpp_utils:get_children(not_xml)).

get_children_2_by_name_test() ->
    Query = #xmlel{name = <<"query">>, attrs = [], children = []},
    Body = #xmlel{name = <<"body">>, attrs = [], children = []},
    El = #xmlel{name = <<"iq">>, attrs = [], children = [Query, Body]},
    ?assertEqual([Query], claws_xmpp_utils:get_children(El, <<"query">>)).

get_children_2_no_match_test() ->
    Child = #xmlel{name = <<"query">>, attrs = [], children = []},
    El = #xmlel{name = <<"iq">>, attrs = [], children = [Child]},
    ?assertEqual([], claws_xmpp_utils:get_children(El, <<"body">>)).

get_children_2_non_xmlel_test() ->
    ?assertEqual([], claws_xmpp_utils:get_children(not_xml, <<"query">>)).

%% get_child tests

get_child_found_test() ->
    Query = #xmlel{name = <<"query">>, attrs = [], children = []},
    Body = #xmlel{name = <<"body">>, attrs = [], children = []},
    El = #xmlel{name = <<"iq">>, attrs = [], children = [Query, Body]},
    ?assertEqual(Body, claws_xmpp_utils:get_child(El, <<"body">>)).

get_child_first_test() ->
    Query = #xmlel{name = <<"query">>, attrs = [], children = []},
    El = #xmlel{name = <<"iq">>, attrs = [], children = [Query]},
    ?assertEqual(Query, claws_xmpp_utils:get_child(El, <<"query">>)).

get_child_not_found_test() ->
    Query = #xmlel{name = <<"query">>, attrs = [], children = []},
    El = #xmlel{name = <<"iq">>, attrs = [], children = [Query]},
    ?assertEqual(undefined, claws_xmpp_utils:get_child(El, <<"body">>)).

get_child_empty_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [], children = []},
    ?assertEqual(undefined, claws_xmpp_utils:get_child(El, <<"query">>)).

get_child_non_xmlel_test() ->
    ?assertEqual(undefined, claws_xmpp_utils:get_child(not_xml, <<"q">>)).

%% get_cdata tests

get_cdata_found_test() ->
    El = #xmlel{name = <<"body">>, attrs = [],
                children = [{xmlcdata, <<"hello">>}]},
    ?assertEqual(<<"hello">>, claws_xmpp_utils:get_cdata(El)).

get_cdata_skip_xmlel_test() ->
    Inner = #xmlel{name = <<"br">>, attrs = [], children = []},
    El = #xmlel{name = <<"body">>, attrs = [],
                children = [Inner, {xmlcdata, <<"text">>}]},
    ?assertEqual(<<"text">>, claws_xmpp_utils:get_cdata(El)).

get_cdata_undefined_test() ->
    El = #xmlel{name = <<"body">>, attrs = [], children = []},
    ?assertEqual(undefined, claws_xmpp_utils:get_cdata(El)).

get_cdata_non_xmlel_test() ->
    ?assertEqual(undefined, claws_xmpp_utils:get_cdata(not_xml)).

%% get_attr tests

get_attr_found_test() ->
    El = #xmlel{name = <<"iq">>,
                attrs = [{<<"type">>, <<"get">>}],
                children = []},
    ?assertEqual(<<"get">>, claws_xmpp_utils:get_attr(El, <<"type">>)).

get_attr_not_found_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [], children = []},
    ?assertEqual(undefined, claws_xmpp_utils:get_attr(El, <<"type">>)).

get_attr_with_default_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [], children = []},
    ?assertEqual(<<"set">>,
                 claws_xmpp_utils:get_attr(El, <<"type">>, <<"set">>)).

get_attr_from_list_test() ->
    El = #xmlel{name = <<"iq">>,
                attrs = [{<<"type">>, <<"get">>}],
                children = []},
    ?assertEqual(<<"get">>, claws_xmpp_utils:get_attr([El], <<"type">>)).

get_attr_default_non_xmlel_test() ->
    ?assertEqual(<<"def">>,
                 claws_xmpp_utils:get_attr(not_xml, <<"type">>, <<"def">>)).

%% get_attr_deep tests

get_attr_deep_at_root_test() ->
    El = #xmlel{name = <<"iq">>,
                attrs = [{<<"type">>, <<"get">>}],
                children = []},
    ?assertEqual(<<"get">>, claws_xmpp_utils:get_attr_deep(El, <<"type">>)).

get_attr_deep_in_child_test() ->
    Child = #xmlel{name = <<"query">>,
                   attrs = [{<<"xmlns">>, <<"jabber:iq:roster">>}],
                   children = []},
    El = #xmlel{name = <<"iq">>, attrs = [], children = [Child]},
    ?assertEqual(<<"jabber:iq:roster">>,
                 claws_xmpp_utils:get_attr_deep(El, <<"xmlns">>)).

get_attr_deep_not_found_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [], children = []},
    ?assertEqual(undefined,
                 claws_xmpp_utils:get_attr_deep(El, <<"missing">>)).

get_attr_deep_with_default_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [], children = []},
    ?assertEqual(<<"default">>,
                 claws_xmpp_utils:get_attr_deep(El, <<"missing">>,
                                                 <<"default">>)).

%% get_jid_node and get_jid_domain tests

get_jid_node_test() ->
    ?assertEqual(<<"user">>,
                 claws_xmpp_utils:get_jid_node(<<"user@domain.com">>)).

get_jid_node_no_node_test() ->
    ?assertEqual(undefined,
                 claws_xmpp_utils:get_jid_node(<<"domain.com">>)).

get_jid_domain_test() ->
    ?assertEqual(<<"domain.com">>,
                 claws_xmpp_utils:get_jid_domain(<<"user@domain.com">>)).

get_jid_domain_no_node_test() ->
    ?assertEqual(undefined,
                 claws_xmpp_utils:get_jid_domain(<<"domain.com">>)).

%% to_bare_jid tests

to_bare_jid_full_test() ->
    ?assertEqual(<<"user@domain.com">>,
                 claws_xmpp_utils:to_bare_jid(<<"user@domain.com/res">>)).

to_bare_jid_already_bare_test() ->
    ?assertEqual(<<"user@domain.com">>,
                 claws_xmpp_utils:to_bare_jid(<<"user@domain.com">>)).

%% replace_children tests

replace_children_empty_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [],
                children = [#xmlel{name = <<"q">>, attrs = [], children = []}]},
    Result = claws_xmpp_utils:replace_children(El, []),
    ?assertEqual([], Result#xmlel.children).

replace_children_new_test() ->
    El = #xmlel{name = <<"iq">>, attrs = [], children = []},
    New = #xmlel{name = <<"query">>, attrs = [], children = []},
    Result = claws_xmpp_utils:replace_children(El, [New]),
    ?assertEqual([New], Result#xmlel.children).

%% part_jid tests

part_jid_full_test() ->
    {Node, Domain, Resource} =
        claws_xmpp_utils:part_jid(<<"user@domain.com/res">>),
    ?assertEqual(<<"user">>, Node),
    ?assertEqual(<<"domain.com">>, Domain),
    ?assertEqual(<<"res">>, Resource).

part_jid_bare_test() ->
    {Node, Domain, Resource} =
        claws_xmpp_utils:part_jid(<<"user@domain.com">>),
    ?assertEqual(<<"user">>, Node),
    ?assertEqual(<<"domain.com">>, Domain),
    ?assertEqual(<<>>, Resource).

%% escape_using_entities tests

escape_entities_list_test() ->
    ?assertEqual("&amp;&lt;&gt;&quot;&apos;",
                 claws_xmpp_utils:escape_using_entities("&<>\"'")).

escape_entities_binary_test() ->
    ?assertEqual(<<"&amp;&lt;&gt;&quot;&apos;">>,
                 claws_xmpp_utils:escape_using_entities(<<"&<>\"'">>)).

escape_entities_plain_text_test() ->
    ?assertEqual(<<"hello">>,
                 claws_xmpp_utils:escape_using_entities(<<"hello">>)).

%% unescape tests

unescape_binary_test() ->
    ?assertEqual(<<"&">>, claws_xmpp_utils:unescape(<<"&amp;">>)).

unescape_list_test() ->
    ?assertEqual("&", claws_xmpp_utils:unescape("&amp;")).

unescape_no_entities_test() ->
    ?assertEqual(<<"hello">>, claws_xmpp_utils:unescape(<<"hello">>)).

%% is_whitespace tests

is_whitespace_true_test() ->
    ?assert(claws_xmpp_utils:is_whitespace({xmlcdata, <<" \t\n\r">>})).

is_whitespace_false_test() ->
    ?assertNot(claws_xmpp_utils:is_whitespace({xmlcdata, <<"hello">>})).

is_whitespace_non_cdata_test() ->
    ?assertNot(claws_xmpp_utils:is_whitespace(
        #xmlel{name = <<"x">>, attrs = [], children = []})).

is_whitespace_empty_test() ->
    ?assert(claws_xmpp_utils:is_whitespace({xmlcdata, <<>>})).

%% rwp tests

rwp_removes_whitespace_test() ->
    El = #xmlel{name = <<"x">>, attrs = [],
                children = [{xmlcdata, <<" ">>},
                            {xmlcdata, <<"data">>}]},
    Result = claws_xmpp_utils:rwp(El),
    ?assertEqual([{xmlcdata, <<"data">>}], Result#xmlel.children).

rwp_keeps_content_test() ->
    El = #xmlel{name = <<"x">>, attrs = [],
                children = [{xmlcdata, <<"hello">>}]},
    Result = claws_xmpp_utils:rwp(El),
    ?assertEqual([{xmlcdata, <<"hello">>}], Result#xmlel.children).

%% elem_to_binary and binary_to_elem tests

elem_to_binary_test() ->
    application:ensure_all_started(fast_xml),
    El = #xmlel{name = <<"ping">>,
                attrs = [{<<"xmlns">>, <<"urn:xmpp:ping">>}],
                children = []},
    Result = claws_xmpp_utils:elem_to_binary(El),
    ?assertEqual(<<"<ping xmlns='urn:xmpp:ping'/>">>, Result).

binary_to_elem_test() ->
    application:ensure_all_started(fast_xml),
    El = claws_xmpp_utils:binary_to_elem(
        <<"<ping xmlns='urn:xmpp:ping'/>">>),
    ?assertEqual(<<"ping">>, El#xmlel.name).

binary_to_elem_from_list_test() ->
    application:ensure_all_started(fast_xml),
    El = claws_xmpp_utils:binary_to_elem(
        "<ping xmlns='urn:xmpp:ping'/>"),
    ?assertEqual(<<"ping">>, El#xmlel.name).

elems_to_binary_empty_test() ->
    ?assertEqual(<<>>, claws_xmpp_utils:elems_to_binary([])).

elems_to_binary_multiple_test() ->
    application:ensure_all_started(fast_xml),
    E1 = #xmlel{name = <<"a">>, attrs = [], children = []},
    E2 = #xmlel{name = <<"b">>, attrs = [], children = []},
    Result = claws_xmpp_utils:elems_to_binary([E1, E2]),
    ?assertEqual(<<"<a/><b/>">>, Result).

%% iso_date tests

iso_date_test() ->
    T = {1457, 0, 500000},
    Result = claws_xmpp_utils:iso_date(T),
    ?assertMatch([_ | _], Result),
    %% Should contain T separator and end with Z
    ?assertNotEqual(nomatch, string:find(Result, "T")),
    ?assertNotEqual(nomatch, string:find(Result, "Z")).
