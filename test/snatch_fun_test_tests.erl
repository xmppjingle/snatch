-module(snatch_fun_test_tests).

-compile([warnings_as_errors, debug_info]).

-export([init/1, terminate/2, handle_info/2]).
-export([check_data/3]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("fast_xml/include/fxml.hrl").
-include("snatch.hrl").

ping_test_() ->
    snatch_fun_test:check([
        "xmpp_comp_ping",
        "xmpp_comp_custom"
    ]).

ping_again_test_() ->
    %% this test is only to check it's possible to get more than
    %% one functional test block.
    snatch_fun_test:check([
        "xmpp_comp_ping"
    ]).

check_data([#xmlel{}], [#xmlel{}], Map) ->
    ?assertMatch(#{ <<"data">> := <<"abc">> }, Map),
    ok.

-define(JID_USER, <<"bob@localhost/pc">>).
-define(JID_COMP, <<"alice.localhost">>).

-define(PING_REQUEST,
        #xmlel{name = <<"iq">>,
               attrs = [{<<"type">>, <<"get">>},
                        {<<"from">>, ?JID_USER},
                        {<<"to">>, ?JID_COMP},
                        {<<"id">>, <<"test_bot">>}],
               children = [
                   #xmlel{name = <<"ping">>,
                          attrs = [{<<"xmlns">>, <<"urn:xmpp:ping">>}]}
               ]}).
-define(PING_RESPONSE,
        #xmlel{name = <<"iq">>,
               attrs = [{<<"type">>, <<"result">>},
                        {<<"to">>, ?JID_USER},
                        {<<"from">>, ?JID_COMP},
                        {<<"id">>, <<"test_bot">>}],
               children = []}).

-define(QUERY_REQUEST,
        #xmlel{name = <<"iq">>,
               attrs = [{<<"type">>, <<"get">>},
                        {<<"from">>, ?JID_USER},
                        {<<"to">>, ?JID_COMP},
                        {<<"id">>, <<"test_bot">>}],
               children = [
                   #xmlel{name = <<"query">>,
                          attrs = [{<<"xmlns">>, <<"urn:custom">>}]}
               ]}).
-define(QUERY_RESPONSE,
        #xmlel{name = <<"iq">>,
               attrs = [{<<"type">>, <<"result">>},
                        {<<"to">>, ?JID_USER},
                        {<<"from">>, ?JID_COMP},
                        {<<"id">>, <<"test_bot">>}],
               children = [
                            #xmlel{name = <<"query">>,
                                   attrs = [{<<"xmlns">>,
                                             <<"urn:custom">>}],
                                   children = [
                                       #xmlel{name = <<"item">>,
                                              children = [{xmlcdata, <<"abc">>}]}
                                   ]}
                          ]}).

init([]) ->
    {ok, []}.

terminate(_Reason, _State) ->
    ok.

handle_info({received, ?QUERY_REQUEST, #via{}}, []) ->
    snatch:send(fxml:element_to_binary(?QUERY_RESPONSE)),
    {noreply, []};

handle_info({received, ?PING_REQUEST}, []) ->
    snatch:send(fxml:element_to_binary(?PING_RESPONSE)),
    {noreply, []}.
