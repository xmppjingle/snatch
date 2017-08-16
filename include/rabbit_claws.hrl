-record(state, {jid, channel, connection, direct_queue, fanout_queue, listener, opts}).

-define(EXCHANGE_DIRECT, <<"xmpp_direct">>).
-define(EXCHANGE_FANOUT, <<"xmpp_fanout">>).
-define(DIRECT, <<"direct">>).
-define(FANOUT, <<"fanout">>).
