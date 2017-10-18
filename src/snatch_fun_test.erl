-module(snatch_fun_test).
-compile([warnings_as_errors]).

-export([
    check/1,
    check/2,
    check/3,
    run/1
]).

-export([send/2]).

-define(DEFAULT_TIMEOUT, 120). % seconds
-define(DEFAULT_VERBOSE, false).

-define(DEFAULT_TIMES, 1).
-define(DEFAULT_STEP_TIMEOUT, 1000). % ms

-define(TEST_PROCESS, test_proc).
-define(TIMEOUT_RECEIVE_ALL, 500). % ms

-include_lib("fast_xml/include/fxml.hrl").
-include_lib("eunit/include/eunit.hrl").

-record(functional, {
    steps = [] :: [term()],
    config :: [proplists:property()]
}).

-record(step, {
    name :: binary(),
    timeout = ?DEFAULT_STEP_TIMEOUT :: pos_integer(),
    actions
}).

check(Tests) ->
    check(Tests, ?DEFAULT_TIMEOUT, ?DEFAULT_VERBOSE).

check(Tests, Timeout) ->
    check(Tests, Timeout, ?DEFAULT_VERBOSE).

check(Tests, Timeout, Verbose) ->
    {timeout, Timeout,
        {setup,
            fun() -> start_suite(Verbose) end,
            fun(_) -> stop_suite() end,
            [ run(Test) || Test <- Tests ]
        }
    }.

send(PingResponse, <<"unknown">>) ->
    ?TEST_PROCESS ! {send, PingResponse},
    ok.

start_suite(_Verbose) ->
    {ok, _PID} = net_kernel:start([snatch@localhost, shortnames]),
    application:start(fast_xml),
    timer:sleep(1000),
    ok.

stop_suite() ->
    ok = application:stop(fast_xml),
    ok = application:unload(fast_xml),
    ok = net_kernel:stop(),
    ok.

run(Test) ->
    {" ** TEST => " ++ Test, {spawn, {setup,
        fun() -> parse_file(Test) end,
        fun(Functional) ->
            run_start(Functional) ++
            run_steps(Functional) ++
            run_stop(Functional)
        end
    }}}.

get_cfg(Name, Config) ->
    proplists:get_value(Name, Config, undefined).

run_start(#functional{config = Config}) ->
    [{"start",
        fun() ->
            Module = binary_to_atom(get_cfg(snatch, Config), utf8),
            true = register(?TEST_PROCESS, self()),
            {ok, _PID} = snatch:start_link(?MODULE, Module, [])
        end}].

run_steps(#functional{steps = Steps}) ->
    lists:map(fun run_step/1, Steps).

run_stop(#functional{}) ->
    [{"stop",
        fun() ->
            snatch:stop(),
            true = unregister(?TEST_PROCESS)
        end}].

run_step(#step{name = Name, actions = Actions}) ->
    [{Name, fun() ->
        lists:foldl(fun run_action/2, {[], [], #{}}, Actions)
      end}].

run_action({vars, VarsMap}, {ExpectedStanzas, ReceivedStanzas, Map}) ->
    NewMap = maps:merge(Map, VarsMap),
    {ExpectedStanzas, ReceivedStanzas, NewMap};

run_action({send, Stanzas}, {ExpectedStanzas, ReceivedStanzas, Map}) ->
    {ProcessedStanzas, NewMap} = lists:foldl(fun process_action/2,
                                             {[], Map}, Stanzas),
    lists:foreach(fun snatch:received/1, ProcessedStanzas),
    {ExpectedStanzas, ReceivedStanzas, NewMap};

run_action({expected, Stanzas}, {ExpectedStanzas, OldRecvStanzas, Map}) ->
    ReceivedStanzas = receive_stanzas([]),
    NewExpectedStanzas = ExpectedStanzas ++ Stanzas,
    NewMap = check_stanzas(ReceivedStanzas, NewExpectedStanzas, Map),
    {NewExpectedStanzas, OldRecvStanzas ++ ReceivedStanzas, NewMap};

run_action({check, {M, F}}, {ExpectedStanzas, ReceivedStanzas, Map}) ->
    ok = apply(M, F, [ExpectedStanzas, ReceivedStanzas, Map]).

process_action(#xmlel{attrs = Attrs, children = Children} = El,
               {ProcessedStanzas, Map}) ->
    ProcessedAttrs = lists:map(fun
        ({AttrKey, <<"{{",_/binary>> = Value}) ->
            RE = <<"^\\{\\{([^}]+)\\}\\}$">>,
            Opts = [global, {capture, all, binary}],
            case re:run(Value, RE, Opts) of
                {match, [[Value, Key]]} -> {AttrKey, maps:get(Key, Map)};
                nomatch -> {AttrKey, Value}
            end;
        (Attr) -> Attr
    end, Attrs),
    ProcessedChildren = lists:map(fun
        ({xmlcdata, CData}) ->
            RE = <<"\\{\\{([^}]+)\\}\\}">>,
            Opts = [global],
            case re:run(CData, RE, Opts) of
                {match, [[CData|Keys]]} ->
                    lists:foldl(fun(Key, CD) ->
                        Val = maps:get(Key, Map),
                        ReplaceKey = <<"\\{\\{", Key/binary, "\\}\\}">>,
                        iolist_to_binary(re:replace(CD, ReplaceKey, Val, Opts))
                    end, CData, Keys);
                nomatch ->
                    CData
            end;
        (#xmlel{} = Child) ->
            hd(element(1, process_action(Child, {[], Map})))
    end, Children),
    Stanza = El#xmlel{attrs = ProcessedAttrs, children = ProcessedChildren},
    {ProcessedStanzas ++ [Stanza], Map}.

check_stanzas([], [], Map) ->
    Map;
check_stanzas([], ExpectedStanzas, Map) ->
    XMLStanza = lists:foldl(fun(ExpectedStanza, Text) ->
        <<Text/binary, (fxml:element_to_binary(ExpectedStanza))/binary, "\n">>
    end, <<>>, ExpectedStanzas),
    ?debugFmt("~n~n-----------~nMissing stanza(s):~n~s~n"
              "~nMap => ~p~n-----------~n",
              [XMLStanza, Map]),
    erlang:halt(1);
check_stanzas([RecvStanza|ReceivedStanzas], ExpectedStanzas, Map) ->
    ExpectedStanza = lists:foldl(fun
        (ExpectedStanza, false) ->
            case check_stanza(RecvStanza, ExpectedStanza) of
                true -> ExpectedStanza;
                false -> false
            end;
        (_, ExpectedStanza) ->
            ExpectedStanza
    end, false, ExpectedStanzas),
    case ExpectedStanza of
        false ->
            XMLStanza = fxml:element_to_binary(RecvStanza),
            ?debugFmt("~n~n-----------~nUnexpected stanza:~n~s~n"
                      "~nMap => ~p~n-----------~n",
                      [XMLStanza, Map]),
            erlang:halt(1);
        ExpectedStanza ->
            ok
    end,
    NewExpectedStanzas = ExpectedStanzas -- [ExpectedStanza],
    NewMap = lists:foldl(fun
        ({value, Key, Value}, M) -> M#{Key => Value}
    end, Map, receive_updates([])),
    check_stanzas(ReceivedStanzas, NewExpectedStanzas, NewMap).

check_stanza(El, El) -> true;
check_stanza({xmlcdata, CData}, {xmlcdata, CData}) -> true;
check_stanza(#xmlel{name = Name} = El1, #xmlel{name = Name} = El2) ->
    case check_attrs(lists:sort(El1#xmlel.attrs),
                     lists:sort(El2#xmlel.attrs)) of
        true when length(El1#xmlel.children) =:= length(El2#xmlel.children) ->
            Els = lists:zip(lists:sort(El1#xmlel.children),
                            lists:sort(El2#xmlel.children)),
            lists:all(fun({E1, E2}) -> check_stanza(E1, E2) end, Els);
        _ ->
            false
    end;
check_stanza({xmlcdata, CData1}, {xmlcdata, <<"{{", _/binary>> = CData2}) ->
    RE = <<"^\\{\\{([^}]+)\\}\\}$">>,
    Opts = [global, {capture, all, binary}],
    {match, [[CData2, Var]]} = re:run(CData2, RE, Opts),
    self() ! {value, Var, CData1},
    true;
check_stanza(_, _) ->
    false.

check_attrs(Attrs, Attrs) -> true;
check_attrs([Attr|Attrs1], [Attr|Attrs2]) ->
    check_attrs(Attrs1, Attrs2);
check_attrs([{Key, Val1}|Attrs1], [{Key, <<"{{",_/binary>> = Val2}|Attrs2]) ->
    RE = <<"^\\{\\{([^}]+)\\}\\}$">>,
    Opts = [global, {capture, all, binary}],
    {match, [[Val2, Var]]} = re:run(Val2, RE, Opts),
    self() ! {value, Var, Val1},
    check_attrs(Attrs1, Attrs2);
check_attrs(_A1, _A2) ->
    false.

receive_updates(Updates) ->
    receive
        {value, _, _} = Value -> receive_updates([Value|Updates])
    after ?TIMEOUT_RECEIVE_ALL ->
        Updates
    end.

receive_stanzas(ReceivedStanzas) ->
    receive
        {send, XMLStanza} ->
            Stanza = fxml_stream:parse_element(XMLStanza),
            receive_stanzas([Stanza|ReceivedStanzas])
    after ?TIMEOUT_RECEIVE_ALL ->
        ReceivedStanzas
    end.

parse_file(Test) ->
    {ok, BaseDir} = file:get_cwd(),
    File = BaseDir ++ "/test/functional/" ++ Test ++ ".xml",
    {ok, XML} = file:read_file(File),
    Parsed = case fxml_stream:parse_element(XML) of
        #xmlel{} = P ->
            P;
        Error ->
            ?debugFmt("~n~n---------------~n~s~n~p~n~n", [File, Error]),
            erlang:halt(2)
    end,
    Cleaned = clean_spaces(Parsed),
    lists:foldl(fun(XmlEl, #functional{steps = Steps} = F) ->
        case parse(XmlEl) of
            [#step{}|_] = NewSteps ->
                F#functional{steps = Steps ++ NewSteps};
            [{_, _}|_] = Config ->
                F#functional{config = Config};
            [] -> F
        end
    end, #functional{}, Cleaned#xmlel.children).

clean_spaces(#xmlel{children = []} = XmlEl) ->
    XmlEl;
clean_spaces(#xmlel{children = Children} = XmlEl) ->
    C = lists:filtermap(fun
        ({xmlcdata, Content}) -> trim(Content) =/= <<>>;
        (#xmlel{} = X) -> {true, clean_spaces(X)}
    end, Children),
    XmlEl#xmlel{children = C}.

trim(Text) ->
    re:replace(Text, "^\\s+|\\s+$", "", [{return, binary}, global]).

get_cdata(#xmlel{children = Children}) ->
    get_cdata(Children, <<>>).

get_cdata([{xmlcdata, C}|Children], CData) ->
    get_cdata(Children, <<CData/binary, C/binary>>);
get_cdata([#xmlel{children = []}|Children], CData) ->
    get_cdata(Children, CData);
get_cdata([#xmlel{children = C}|Children], CData) ->
    get_cdata(Children, get_cdata(C, CData));
get_cdata([], CData) ->
    CData.

% get_attr(Name, #xmlel{} = XmlEl) when is_binary(Name) ->
%     get_attr(Name, XmlEl, undefined).

get_attr(Name, #xmlel{attrs = Attrs}, Default) when is_binary(Name) ->
    case lists:keyfind(Name, 1, Attrs) of
        false -> Default;
        {Name, Value} -> Value
    end.

get_attr_atom(Name, #xmlel{} = XmlEl) ->
    get_attr_atom(Name, XmlEl, undefined).

get_attr_atom(Name, #xmlel{attrs = Attrs}, Default) when is_atom(Default) ->
    case lists:keyfind(Name, 1, Attrs) of
        false -> Default;
        {Name, Value} -> binary_to_atom(Value, utf8)
    end.

get_attr_int(Name, #xmlel{attrs = Attrs}, Default) when is_integer(Default) ->
    case lists:keyfind(Name, 1, Attrs) of
        false -> Default;
        {Name, Value} -> binary_to_integer(Value)
    end.

parse(#xmlel{name = <<"config">>, children = Configs}) ->
    lists:flatmap(fun
        (#xmlel{name = <<"snatch">>, attrs = [{<<"module">>, Name}]}) ->
            [{snatch, Name}]
    end, Configs);

parse(#xmlel{name = <<"steps">>, children = Steps}) ->
    lists:map(fun parse_step/1, Steps).


parse_step(#xmlel{children = Actions} = Step) ->
    Timeout = get_attr_int(<<"timeout">>, Step, ?DEFAULT_STEP_TIMEOUT),
    #step{name = get_attr(<<"name">>, Step, <<"noname">>),
          timeout = Timeout,
          actions = lists:map(fun parse_action/1, Actions)}.

parse_action(#xmlel{name = <<"vars">>, children = Vars}) ->
    Map = lists:foldl(fun
        (#xmlel{name = <<"value">>, attrs = [{<<"key">>, Key}]} = El, M) ->
            M#{ Key => get_cdata(El) };
        (#xmlel{name = Name}, M) when Name =/= <<"value">> ->
            M
    end, #{}, Vars),
    {vars, Map};

parse_action(#xmlel{name = <<"send">>, children = Send}) ->
    {send, Send};

parse_action(#xmlel{name = <<"expected">>, children = Expected}) ->
    {expected, Expected};

parse_action(#xmlel{name = <<"check">>} = Check) ->
    M = get_attr_atom(<<"module">>, Check),
    F = get_attr_atom(<<"function">>, Check),
    {check, {M, F}}.
