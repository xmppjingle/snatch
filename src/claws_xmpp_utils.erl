-module(claws_xmpp_utils).

-include_lib("fast_xml/include/fxml.hrl").
-include("claws_xmpp.hrl").

-export([
    iq/4,
    iq/5,    
    empty_iq/4,
    empty_iq/3,    
    iq_set/4,
    iq_result/1,
	  iq_result/3,
    iq_error/3,
    iq_error/1,
    presence/4,
    presence/5,
    message/5,
    empty_presence/4,
    empty_presence/3,
    presence_subscribe/1,
    presence_subscribed/1,
    presence_available/3,
    presence_available/4,
    presence_unavailable/3,
    normalize_jid/1,
    get_children/1,
    get_children/2,
    get_child/2,
    get_jid_node/1,
    get_jid_domain/1,
    to_bare_jid/1,
    gen_uuid/0,
    gen_uuid_bin/0,
    get_attr/3,
    get_attr/2,
    replace_children/2,
    part_jid/1,
    elem_to_binary/1,
    elems_to_binary/1,
    binary_to_elem/1,
    escape_using_entities/1,
    rwp/1,
    is_whitespace/1,
    unescape/1,
    get_attr_deep/2,
    get_attr_deep/3,
    get_cdata/1,
    get_name/1
]).

is_whitespace({xmlcdata, CData}) ->
    is_whitespace2(CData);
is_whitespace(_) ->
    false.

is_whitespace2(<<C:8, Rest/binary>>)
  when C == $\s; C == $\t; C == $\n; C == $\r ->
    is_whitespace2(Rest);
is_whitespace2(<<>>) ->
    true;
is_whitespace2(_CData) ->
    false.

rwp(#xmlel{children = Children} = P) ->
  Cs = [  X || X <- Children, not is_whitespace(X) andalso X /= undefined],
  Ch = [ rwp(X) || X <- Cs],
  P#xmlel{children = Ch};
rwp({xmlcdata, _} = CData) ->
  case is_whitespace(CData) of
    true ->
      undefined;
    _ ->  
      CData
  end.

normalize_jid(JID) ->
    case JID of
        {undefined, D, undefined} ->
            <<D/binary>>;
        {N, D, undefined} ->
            <<N/binary,<<"@">>/binary,D/binary>>;
        {N, D, R} ->
            <<N/binary,<<"@">>/binary,D/binary,<<"/">>/binary,R/binary>>;
        BJID when is_binary(JID) ->
            BJID;
        LJID when is_list(JID) ->
            erlang:list_to_binary(LJID);
        _ ->
            undefined
    end.

get_name(#xmlel{name = Name}) ->
    Name;
get_name(_) ->
    <<>>.

get_children(#xmlel{children = Children}) ->
    Children;
get_children(_) ->
    [].

get_children(#xmlel{children = Children}, Name) ->
    [ E || #xmlel{name = N} = E <- Children, N == Name];
get_children(_, _) ->
    [].

get_child(#xmlel{children = []}, _) ->
    undefined;
get_child(#xmlel{children = [ #xmlel{name = Name} = E | _R]}, Name) ->
    E;
get_child(#xmlel{children = [ #xmlel{} | R]} = Parent, Name) ->
    get_child(Parent#xmlel{children = R}, Name);
get_child(_, _) ->
    undefined.

get_cdata(#xmlel{children = [{xmlcdata, CData}|_]}) ->
    CData;
get_cdata(#xmlel{children = [_H|T]} = E) ->
    get_cdata(E#xmlel{children = T});
get_cdata(_) -> undefined.

get_attr_deep(Elem, Name) ->
  get_attr_deep(Elem, Name, undefined).

get_attr_deep(#xmlel{children = Children} = E, Name, Default) ->
    A = case get_attr(E, Name, undefined) of
      undefined ->
        get_attr_deep(Children, Name, Default);
      Value ->
        Value
    end,
    case A of
      undefined ->
        Default;
      A -> A
    end;
get_attr_deep([#xmlel{}=E|T], Name, _) ->
    case get_attr_deep(E, Name, undefined) of
      undefined -> 
        get_attr_deep(T, Name, undefined);
      Value ->
        Value
    end;
get_attr_deep([], _, _) ->
  undefined. 

get_attr(Elem, Name) ->
  get_attr(Elem, Name, undefined).

get_attr(#xmlel{attrs = Attrs}, Name, Default) ->
    proplists:get_value(Name, Attrs, Default);
get_attr([#xmlel{}=E|_], Name, Default) ->
    get_attr(E, Name, Default);
get_attr(_, _, Default) ->
    Default.

get_jid_node(Jid) ->
  case re:split(Jid, "@") of
    [H, _] -> H;
    _else -> undefined
  end.

get_jid_domain(Jid) ->
  case re:split(Jid, "@") of
    [_, R] -> R;
    _else -> undefined
  end.

to_bare_jid(Jid) ->
  case re:split(Jid, "/") of
    [H, _] -> H;
    _else -> Jid
  end.

replace_children(#xmlel{} = Elem, []) ->
  Elem#xmlel{children = []};
replace_children(#xmlel{} = Elem, [#xmlel{}|_] = Children) ->
  Elem#xmlel{children = Children}.

gen_uuid() ->
  uuid:uuid_to_string(uuid:get_v4(strong), binary_standard).

gen_uuid_bin() ->
  list_to_binary(re:replace(gen_uuid(), "-", [], [global, {return, list}])).

part_jid(JID) when is_binary(JID) ->
  case re:split(JID, "/") of
    [Bare, Resource] -> 
      ok;
    Bare -> 
      Resource = <<>>
  end,
  case re:split(Bare, "@") of
    [Node, Domain] ->
      ok;
    Domain ->
      Node = <<>>
  end,
  {Node, Domain, Resource}.

iq(Type, From, To, ID, Query) ->
  <<"<iq ",
    "type='", Type/binary, "' ",
    "from='", From/binary, "' ",
    "to='", To/binary, "' ",
    "id='", ID/binary, "'>",
    Query/binary, "</iq>">>.

iq(Type, To, ID, Query) ->
  <<"<iq ",
    "type='", Type/binary, "' ",
    "to='", To/binary, "' ",
    "id='", ID/binary, "'>",
    Query/binary, "</iq>">>.

empty_iq(Type, From, To, ID) ->
  <<"<iq ",
    "type='", Type/binary, "' ",
    "from='", From/binary, "' ",
    "to='", To/binary, "' ",
    "id='", ID/binary, "'/>">>.

empty_iq(Type, To, ID) ->
  <<"<iq ",
    "type='", Type/binary, "' ",
    "to='", To/binary, "' ",
    "id='", ID/binary, "'/>">>.

iq_set(From, To, ID, Query) ->
  iq(<<"set">>, From, To, ID, Query).

iq_result(From, To, ID) ->
    empty_iq(<<"result">>, From, To, ID).

iq_error(From, To, ID) ->
    empty_iq(<<"error">>, From, To, ID).

iq_error(#iq{from = From, to = To, id = ID}) ->
    empty_iq(<<"error">>, To, From, ID).

iq_result(#iq{from = From, to = To, id = ID}) ->
  iq_result(To, From, ID).

presence(Type, From, To, ID, Query) ->
  <<"<presence ",
    "type='", Type/binary, "' ",
    "from='", From/binary, "' ",
    "to='", To/binary, "' ",
    "id='", ID/binary, "'>",
    Query/binary, "</presence>">>.

presence(Type, To, ID, Query) ->
  <<"<presence ",
    "type='", Type/binary, "' ",
    "to='", To/binary, "' ",
    "id='", ID/binary, "'>",
    Query/binary, "</presence>">>.

message(Type, From, To, ID, Query) ->
  <<"<message ",
    "type='", Type/binary, "' ",
    "from='", From/binary, "' ",
    "to='", To/binary, "' ",
    "id='", ID/binary, "'>",
    Query/binary, "</message>">>.

empty_presence(Type, From, To, ID) ->
  <<"<presence ",
    "type='", Type/binary, "' ",
    "from='", From/binary, "' ",
    "to='", To/binary, "' ",
    "id='", ID/binary, "'/>">>.

empty_presence(Type, To, ID) ->
  <<"<presence ",
    "type='", Type/binary, "' ",
    "to='", To/binary, "' ",
    "id='", ID/binary, "'/>">>.

empty_presence(Type, To) ->
  <<"<presence ",
    "type='", Type/binary, "' ",
    "to='", To/binary, "'/>">>.

presence_available(From, To, ID) ->
  empty_presence(<<"available">>, From, To, ID).

presence_available(From, To, ID, Query) ->
  presence(<<"available">>, From, To, ID, Query).

presence_unavailable(From, To, ID) ->
    empty_presence(<<"unavailable">>, From, To, ID).

presence_subscribe(To) ->
    empty_presence(<<"subscribe">>, To).

presence_subscribed(To) ->
    empty_presence(<<"subscribed">>, To).

elems_to_binary([]) -> <<>>;
elems_to_binary([E|R]) -> 
  BinElem = elem_to_binary(E),
  BinRem = elems_to_binary(R),
  <<BinElem/binary, BinRem/binary>>.

elem_to_binary(#xmlel{} = Elem) ->
  fxml:element_to_binary(Elem).

binary_to_elem(Bin) when is_binary(Bin) ->
  fxml_stream:parse_element(Bin);
binary_to_elem(List) when is_list(List) ->
  binary_to_elem(erlang:list_to_binary(List)).

unescape(A) when is_list(A) -> unescape(A, []);
unescape(A) when is_binary(A) -> erlang:list_to_binary(unescape(erlang:binary_to_list(A), [])).
unescape([],Acc) -> lists:reverse(Acc);
unescape([$&,$a,$m,$p,$;|T],Acc) -> unescape(T,[$&|Acc]);
unescape([H|T],Acc) -> unescape(T,[H|Acc]).

escape_using_entities(CData) when is_list(CData) ->
    lists:flatten([case C of
           $& -> "&amp;";
           $< -> "&lt;";
           $> -> "&gt;";
           $" -> "&quot;";
           $' -> "&apos;";
           _  -> C
       end || C <- CData]);

escape_using_entities(CData) when is_binary(CData) ->
    escape_using_entities2(CData, []).

escape_using_entities2(<<C:8, Rest/binary>>, New_CData) ->
    New_C = case C of
    $& -> <<"&amp;">>;
    $< -> <<"&lt;">>;
    $> -> <<"&gt;">>;
    $" -> <<"&quot;">>;
    $' -> <<"&apos;">>;
    _  -> C
      end,
    escape_using_entities2(Rest, [New_C | New_CData]);
escape_using_entities2(<<>>, New_CData) ->
    list_to_binary(lists:reverse(New_CData)).
