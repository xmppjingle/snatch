snatch
======

Lightweight XMPP Client Library for Erlang. This library is intended to handle client connections in an agnostic way. The system is launched using the snatch process and configuring as many claws as you need.

The built-in claws are:

- [XMPP Client](doc/claws_xmpp.md)
- [XMPP Component](doc/claws_xmpp_comp.md)
- [XMPP over HTTP Long-polling](doc/claws_lp.md)
- [XMPP over AMQP](doc/claws_rabbitmq.md)

Installation
------------

The system requires OTP 19+ because we use [gen_statem](http://erlang.org/doc/design_principles/statem.html) and remove the `code_change/3` and `terminate/2`. For OTP 19+ those callbacks are optional.

In the same way we prefer to use [rebar3](http://www.rebar3.org) instead of older versions. To install snatch only needs:

```erlang
{deps, [
    {snatch, {git, "https://github.com/manuel-rubio/snatch.git", {tag, master}}}
]}
```

Or if you are using [erlang.mk](https://erlang.mk) instead, you can use:

```Makefile
DEPS += snatch
dep_snatch = git https://github.com/manuel-rubio/snatch.git master
```

The used dependencies are:

- [xmpp](https://github.com/processone/xmpp) to handle the XMPP packets.
- [amqp_client](https://github.com/jbrisbin/amqp_client) to handle AMQP protocol.

You'll need a C/C++ compiler installed in your system for [fast_xml](https://github.com/processone/fast_xml) and [stringprep](https://github.com/processone/stringprep).

Configuring
-----------

There are no strict configuration for the application. You have to send the specific information when you start the specific process:

```erlang
{ok, PID} = snatch:start_link([claws_xmpp, my_module, []]).
```

This format helps to start snatch using `my_module` as our implementation of the `snatch` behaviour to use the callbacks to implement the behaviour we want to achieve.

The third element (`[]`) are the arguments passed to the `init/1` callback in `my_module`. You can send all of the information you need for your callback.

The specific claws should be started spearately. See the specific information about each one in their specific documentation pages (see above).

Callbacks
---------

You can use this template to develop your own modules:

```
-module(my_own_module).
-behaviour(snatch).

-include_lib("snatch.hrl").
-include_lib("xmpp.hrl").

-export([init/1, handle_info/2, terminate/2]).

-record(state, {}).

init([]) ->
    {ok, #state{}}.

handle_info({connected, _Claw}, State) ->
    {noreply, State};

handle_info({disconnected, _Claw}, State) ->
    {noreply, State};

handle_info({received, _Packet, #via{}}, State) ->
    {noreply, State};

handle_info({received, _Packet}, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
```

The call to the `init/1` function is performed each time the snatch system is started and `terminate/2` when the system is finished properly. Note that in case of internal errors this code will not be called.

The callback `handle_info/2` will be called when a message arrives to snatch.

The events you can receive are:

- `connected`: says the claw (passed as second element in the tuple) is connected properly.
- `disconnected`: says the claw (passed as second element in the tuple) was disconnected.
- `received`: this event has two ways. Only receive a packet (as second element in the tuple) or receive the packet and the `#via{}` information as well. This information gives us information about the way the packet was sent.

The `#via{}` record has the following information:

- `jid` as the JID (Jabber Identification) of the via.
- `exchange` *(only for AMQP)* says the exchange in use for the element.
- `claws` is the module used to receive the message.
- `id` the identification of the packet.

Sending
-------

To send information thru snatch to the claws you can use the following functions:

- `send/1` to send a packet directly to the default claw. The JID will be configured as *unknown* for the claw.
- `send/2` to send a packet using a specific JID (as second param). The JID will be in use to retrieve a route from the internal snatch information.
- `send/3` to send a packet using a specific JID (as second param) and pointing the ID of the packet to be handled properly by the claw.

The packet should be a valid XML construction. Your application is in charge to create it in the way you want.

For example:

```erlang
snatch:send(<<"<presence/>">>).
```

Troubleshooting
---------------

Feel free to create an issue in github to point a bug, flaw or improvement and even send a pull request with a specific change. Read the [LICENSE](LICENSE) if you have doubts about what you can do with the code.

Enjoy!
