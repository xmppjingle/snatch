-module(snatch_echo).
-behaviour(snatch).

-include_lib("snatch/include/snatch.hrl").
-include_lib("fast_xml/include/fxml.hrl").

-export([main/1]).
-export([init/1, handle_info/2, terminate/2]).

%% escript entry point
main(Args) ->
    application:ensure_all_started(snatch),

    %% Parse args: defaults
    Host = get_arg("--xmpp-host", Args, "localhost"),
    Port = list_to_integer(get_arg("--xmpp-port", Args, "5275")),
    Domain = get_arg("--xmpp-domain", Args, "echo.localhost"),
    Password = get_arg("--xmpp-password", Args, "secret"),

    io:format("Starting Snatch echo bot~n"),
    io:format("  XMPP component: ~s:~p domain=~s~n", [Host, Port, Domain]),

    %% Start snatch with this module as handler
    {ok, _} = snatch:start_link(claws_xmpp_comp, ?MODULE, []),

    %% Start the XMPP component claw
    Params = #{
        host => Host,
        port => Port,
        domain => list_to_binary(Domain),
        password => list_to_binary(Password),
        trimmed => true
    },
    {ok, _Pid} = claws_xmpp_comp:start_link(Params),
    claws_xmpp_comp:connect(),

    io:format("Echo bot running. Press Ctrl+C to stop.~n"),

    %% Block forever
    receive
        stop -> ok
    end.

%% snatch callbacks

init([]) ->
    {ok, #{}}.

handle_info({connected, Claw}, State) ->
    io:format("Connected: ~p~n", [Claw]),
    {noreply, State};

handle_info({disconnected, Claw}, State) ->
    io:format("Disconnected: ~p~n", [Claw]),
    {noreply, State};

handle_info({received, Packet, #via{claws = Claws}}, State) ->
    %% Echo with from/to swapped
    case Packet of
        #xmlel{name = Name, attrs = Attrs, children = Children} ->
            From = fxml:get_attr_s(<<"from">>, Attrs),
            To = fxml:get_attr_s(<<"to">>, Attrs),

            %% Swap from/to
            NewAttrs0 = lists:keyreplace(<<"from">>, 1, Attrs,
                                         {<<"from">>, To}),
            NewAttrs1 = lists:keyreplace(<<"to">>, 1, NewAttrs0,
                                         {<<"to">>, From}),

            %% For IQ get -> result
            NewAttrs = case {Name, fxml:get_attr_s(<<"type">>, Attrs)} of
                {<<"iq">>, <<"get">>} ->
                    lists:keyreplace(<<"type">>, 1, NewAttrs1,
                                     {<<"type">>, <<"result">>});
                _ ->
                    NewAttrs1
            end,

            EchoPacket = #xmlel{name = Name, attrs = NewAttrs,
                                children = Children},
            EchoBin = fxml:element_to_binary(EchoPacket),
            snatch:send(EchoBin, From);
        _ ->
            ok
    end,
    {noreply, State};

handle_info({received, _Packet}, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%% Helpers

get_arg(Key, [Key, Value | _Rest], _Default) ->
    Value;
get_arg(Key, [_ | Rest], Default) ->
    get_arg(Key, Rest, Default);
get_arg(_Key, [], Default) ->
    Default.
