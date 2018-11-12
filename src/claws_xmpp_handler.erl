-module(claws_xmpp_handler).

-include_lib("fast_xml/include/fxml.hrl").
-include("snatch.hrl").
-include("claws_xmpp.hrl").

%% API
-export([
    process_xml/4
        ]).

-callback process_iq(Stanza::#xmlel{}, VIA::#via{}, State::any()) -> true|false.
-callback process_presence(Stanza::#xmlel{}, VIA::#via{}, State::any()) -> true|false.
-callback process_message(Stanza::#xmlel{}, VIA::#via{}, State::any()) -> true|false.
-callback process_unknown(Stanza::#xmlel{}, VIA::#via{}, State::any()) -> true|false.

process_xml(#xmlel{name = Class, attrs = Attrs, children = Payload} = Stanza, _Via, State, Handlers)
	when 
		Class == ?IQ orelse
		Class == ?PRESENCE orelse
		Class == ?MESSAGE ->
    ID = proplists:get_value(<<"id">>, Attrs),
    From = proplists:get_value(<<"from">>, Attrs),
    To = proplists:get_value(<<"to">>, Attrs),
    Type = proplists:get_value(<<"type">>, Attrs, <<"">>),
    NS = case Payload of
        [#xmlel{attrs = ChildrenAttrs} | _] ->
            proplists:get_value(<<"xmlns">>, ChildrenAttrs, undefined);
        _ ->
            undefined
         end,
    case Class of
        ?IQ ->
            lists:dropwhile(fun(H) -> 
            	H:process_iq(Type, #iq{from = From, to = To, id = ID, type = Type, ns = NS, payload = Payload, raw = Stanza}, State) /= false end,
            	Handlers);
        ?PRESENCE ->
            lists:dropwhile(fun(H) -> 
            	H:process_presence(Type, #presence{from = From, to = To, id = ID, type = Type, ns = NS, payload = Payload, raw = Stanza}, State) /= false end,
            	Handlers);
        ?MESSAGE ->
        	lists:dropwhile(fun(H) -> 
            	H:process_message(Type, #message{from = From, to = To, id = ID, type = Type, ns = NS, payload = Payload, raw = Stanza}, State) /= false end,
            Handlers);
        _ ->
            ok
    end;											
process_xml(Packet, Via, State, Handlers) ->
	lists:dropwhile(fun(H) -> 
                H:process_unknown(Packet, Via, State) /= false end,
            Handlers).