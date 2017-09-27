Claws XMPP over AMQP
====================

This claw uses AMQP to sends/receives packets to the XMPP Server. There are no officially support for this but snatch could do performs the gateway action configuring an XMPP Component claw and this one. This way everything send from the XMPP Server to the component could be received by our implementation and send back to this claw to be enqueued for another clients.

**DISCLAIMER** This claw has been tested using [RabbitMQ](https://www.rabbitmq.com/). You can use other AMQP servers but we cannot warranty they could works in the same way.

We can start this claw in this way:

```erlang
Params = #{jid => <<"news.example.com/resource">>,
           host => "example.com",
           username => <<"guest">>,
           password => <<"guest">>},
{ok, PID} = claws_rabbitmq:start_link(Params).
```

The options are as follow:

- `jid` the Jabber Identification to use for the component / user. Is intended to be a full JID.
- `host` the AMQP hostname where to be connected.
- `username` the username for the AMQP authentication.
- `password` the password for the AMQP authentication.

The system is following these steps:

1. Connect to the AMQP system.
2. Open a channel.
3. Create and bind queues.

The queues and exhanges created by the claw are the following ones:

- Exchange `xmpp_direct` (direct)
- Exchange `xmpp_fanout` (fanout)
- Queue `xmpp_direct:FullJID` (direct) is created to receive direct messages.
- Queue `xmpp_fanout:FullJID` (fanout) is created to receive messages sent to all of the connected consumers of the full JID.
- Queue `xmpp_direct:BareJID` (direct) is created to receive direct messages to the bare JID. Useful for load balancing and avoid to receive the same stanza in all of the servers connected to the same bare JID.
- Queue `xmpp_fanout:BareJID` (fanout) is created to receive messages sent to all of the servers and when the stanzas should be received for all of the connected servers using the same bare JID.

The way it works is when you receive a packet from AMQP that packet is sent back to snatch and to the implementation with a `#via{}` information and the field `exchange` filled.

If you want to send a stanza, based on the JID, directly (direct) to the other party you can use:

```erlang
claws_rabbitmq:send(<<"<presence/>">>, <<"news.example.com">>).
```

Or using the broadcast (fanout) this wat:

```erlang
claws_rabbitmq:publish(<<"<presence/>">>, <<"news.example.com">>).
```

The use of `snatch:send/2` is limited this time to only direct messages so you can use whatever of them, the snatch one or the claws_rabbitmq one.
