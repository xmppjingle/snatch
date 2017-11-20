-module(snatch_dummy).

-export([start_link/0, handle_info/2]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("fast_xml/include/fxml.hrl").
-include("snatch.hrl").

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

%% NOTE: We can use here a gen_server but I think it's overkill for
%%       the test I want to run.
start_link() ->
    PID = spawn_link(fun loop/0),
    true = register(?MODULE, PID),
    {ok, PID}.

loop() ->
    receive
        stop ->
            ok;
        Data ->
            handle_info(Data, []),
            loop()
    end.

handle_info({received, ?QUERY_REQUEST, #via{}}, []) ->
    snatch:send(fxml:element_to_binary(?QUERY_RESPONSE)),
    {noreply, []};

handle_info({received, ?PING_REQUEST}, []) ->
    snatch:send(fxml:element_to_binary(?PING_RESPONSE)),
    {noreply, []}.
