Claws Kafka
===========

This claw is designed to use Kafka as input/output system thru the use of different topics as input and output streams. The main idea is keep one topic (i.e. `xmpp.in`) as input XMPP flow for *snatch* and another different topic (i.e. `xmpp.out`) as output to send XMPP stanzas to Kafka to be retrieved for a different element.

**IMPORTANT** you MUSTN'T configure `claws_kafka` to use the same topic for input and output. That will create an infinity loop.

This claw should be started as follow:

```erlang
Params = #{endpoints => [{"localhost", 9092}],
           in_topics => [{<<"xmpp.in">>, [0]}],
           out_topic => <<"xmpp.out">>,
           out_partition => 0,
           trimmed => false,
           raw => false},
{ok, PID} = claws_kafka:start_link(Params).
```

This claw is connected directly to the Kafka system when it's started.

The params passed inside of the map for the `start_link/1` function are:

- `endpoints` is a list of tuples where the first element is a string containing the host name or the IP and the second one is the port where to connect to.
- `in_topics` is a list of tuples where the first element is a binary with the name of the topic and the second one is a list of partitions (integer numbers) where to listen/consume messages. If you don't want to use incoming topics you can specify the empty list.
- `out_topic` (optional) is the name of the topic (binary) where to send the messages when the `send/3` function is used. **IMPORTANT** There are no default value, if the out topic is not defined and you try to send something via this claw then the claw crashes.
- `out_partition` (optional) is the number of the partition where the message will be sent. The default the value is 0.
- `trimmed` (optional) is a special option that let you to do more processing in the snatch part. If you configure as `true` the system will remove all of the empty *cdata* entries (only with spaces and/or line feeds).
- `raw` (optional) let you to avoid to use the XML parser and use the received message as is. That means the `#via{}` record received by snatch implementation (or process) will be almost empty (only claw entry will be populated).

**IMPORTANT** The system isn't keeping track of the messages so, if the system is disconnected and connected again, the messages retrieved previously could be retrieved again.
