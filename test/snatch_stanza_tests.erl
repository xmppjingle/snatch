-module(snatch_stanza_tests).
-author('manuel.rubio@veon.com').

-include_lib("fast_xml/include/fxml.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(FROM, "alice@localhost/pc").
-define(TO, "bob@localhost/pc").
-define(ID, "test1").

-define(HEAD, "id='" ?ID "' from='" ?FROM "' to='" ?TO "'").
-define(HEAD_RESP, "id='" ?ID "' from='" ?TO "' to='" ?FROM "'").

-define(SERVICE_UNAVAILABLE,
        "<error code='503' type='cancel'>"
        "<service-unavailable xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>"
        "</error>").

-define(BAD_REQUEST,
        "<error code='400' type='modify'>"
        "<bad-request xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>"
        "</error>").

-define(FORBIDDEN,
        "<error code='403' type='auth'>"
        "<forbidden xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>"
        "</error>").

-define(NOT_FOUND,
        "<error code='404' type='cancel'>"
        "<not-found xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>"
        "</error>").

-define(NOT_ACCEPTABLE,
        "<error code='406' type='modify'>"
        "<not-acceptable xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>"
        "</error>").

-define(INTERNAL_SERVER_ERROR,
        "<error code='500' type='wait'>"
        "<internal-server-error xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>"
        "</error>").

-define(FEATURE_NOT_IMPLEMENTED,
        "<error code='501' type='cancel'>"
        "<feature-not-implemented xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>"
        "</error>").

-define(ERRORS, [{<<"service-unavailable">>, <<?SERVICE_UNAVAILABLE>>},
                 {<<"bad-request">>, <<?BAD_REQUEST>>},
                 {<<"forbidden">>, <<?FORBIDDEN>>},
                 {<<"not-found">>, <<?NOT_FOUND>>},
                 {<<"not-acceptable">>, <<?NOT_ACCEPTABLE>>},
                 {<<"internal-server-error">>, <<?INTERNAL_SERVER_ERROR>>},
                 {<<"feature-not-implemented">>, <<?FEATURE_NOT_IMPLEMENTED>>}]).

iq_test() ->
    application:ensure_all_started(fast_xml),
    Ping = #xmlel{name = <<"ping">>,
                  attrs = [{<<"xmlns">>, <<"urn:xmpp:ping:1">>}]},
    ?assertEqual(<<"<iq type='get' " ?HEAD ">"
                   "<ping xmlns='urn:xmpp:ping:1'/></iq>">>,
                 snatch_stanza:iq(?FROM, ?TO, ?ID, <<"get">>, [Ping])),
    ok.

message_test() ->
    application:ensure_all_started(fast_xml),
    Body = #xmlel{name = <<"body">>, children = [{xmlcdata, <<"hey!">>}]},
    ?assertEqual(<<"<message type='chat' " ?HEAD ">"
                   "<body>hey!</body></message>">>,
                 snatch_stanza:message(?FROM, ?TO, ?ID, <<"chat">>, [Body])),
    ?assertEqual(<<"<message " ?HEAD ">"
                   "<body>hey!</body></message>">>,
                 snatch_stanza:message(?FROM, ?TO, ?ID, undefined, [Body])),
    ok.

message_error_test() ->
    application:ensure_all_started(fast_xml),
    Body = #xmlel{name = <<"body">>, children = [{xmlcdata, <<"hey!">>}]},
    ?assertEqual(<<"<message type='error' " ?HEAD ">"
                   "<body>hey!</body>"
                   ?SERVICE_UNAVAILABLE
                   "</message>">>,
                 snatch_stanza:message_error(?FROM, ?TO, ?ID, [Body],
                                             <<"service-unavailable">>)),
    ok.

iq_resp_test() ->
    application:ensure_all_started(fast_xml),
    Ping = #xmlel{name = <<"ping">>,
                  attrs = [{<<"xmlns">>, <<"urn:xmpp:ping:1">>}]},
    IQPing = #xmlel{name = <<"iq">>,
                    attrs = [{<<"type">>, <<"get">>},
                             {<<"id">>, <<?ID>>},
                             {<<"from">>, <<?FROM>>},
                             {<<"to">>, <<?TO>>}],
                    children = [Ping]},
    ?assertEqual(<<"<iq type='result' " ?HEAD_RESP ">"
                   "<ping xmlns='urn:xmpp:ping:1'/></iq>">>,
                 snatch_stanza:iq_resp(IQPing)),
    ?assertEqual(<<"<iq type='result' " ?HEAD_RESP ">"
                   "<ping xmlns='urn:xmpp:ping:1'/></iq>">>,
                 snatch_stanza:iq_resp(?TO, ?FROM, ?ID, [Ping])),
    ?assertEqual(<<"<iq type='result' " ?HEAD_RESP "/>">>,
                 snatch_stanza:iq_resp(?TO, ?FROM, ?ID)),
    ok.

iq_error_test() ->
    application:ensure_all_started(fast_xml),
    Ping = #xmlel{name = <<"ping">>,
                  attrs = [{<<"xmlns">>, <<"urn:xmpp:ping:1">>}]},
    IQPing = #xmlel{name = <<"iq">>,
                    attrs = [{<<"type">>, <<"get">>},
                             {<<"id">>, <<?ID>>},
                             {<<"from">>, <<?FROM>>},
                             {<<"to">>, <<?TO>>}],
                    children = [Ping]},
    ?assertEqual(<<"<iq type='error' " ?HEAD_RESP ">"
                   "<ping xmlns='urn:xmpp:ping:1'/>"
                   ?SERVICE_UNAVAILABLE
                   "</iq>">>,
                 snatch_stanza:iq_error(IQPing, <<"service-unavailable">>)),
    ?assertEqual(<<"<iq type='error' " ?HEAD_RESP ">"
                   "<ping xmlns='urn:xmpp:ping:1'/>"
                   ?SERVICE_UNAVAILABLE
                   "</iq>">>,
                 snatch_stanza:iq_error(?TO, ?FROM, ?ID, [Ping],
                                        <<"service-unavailable">>)),
    ok.

get_error_test() ->
    application:ensure_all_started(fast_xml),
    lists:foreach(fun({Error, ErrorTag}) ->
        Ping = #xmlel{name = <<"ping">>,
                      attrs = [{<<"xmlns">>, <<"urn:xmpp:ping:1">>}]},
        IQPing = #xmlel{name = <<"iq">>,
                        attrs = [{<<"type">>, <<"get">>},
                                 {<<"id">>, <<?ID>>},
                                 {<<"from">>, <<?FROM>>},
                                 {<<"to">>, <<?TO>>}],
                        children = [Ping]},
        ?assertEqual(<<"<iq type='error' " ?HEAD_RESP ">"
                       "<ping xmlns='urn:xmpp:ping:1'/>",
                       ErrorTag/binary,
                       "</iq>">>,
                     snatch_stanza:iq_error(IQPing, Error))
    end, ?ERRORS),
    ok.
