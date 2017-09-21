-module(snatch_jid).
-compile([warnings_as_errors]).

-export([is_full/1, to_bare/1]).

-include_lib("xmpp.hrl").


-spec is_full(#jid{} | binary()) -> boolean().
%% @doc returns true if the JID is a full JID, false otherwise.
is_full(#jid{resource = <<>>}) ->
    false;

is_full(JID) when is_binary(JID) -> 
    is_full(jid:decode(JID));

is_full(#jid{}) ->
    true;

is_full(_) ->
    false.


-spec to_bare(#jid{} | binary()) -> binary().
%% @doc converts JID to a bare JID in binary format.
to_bare(#jid{user = User, server = Domain}) ->
    <<User/binary, "@", Domain/binary>>;

to_bare(JID) when is_binary(JID) ->
    to_bare(jid:decode(JID)).
