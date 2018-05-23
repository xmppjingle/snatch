

# Module claws_fcm #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)

.

Copyright (c) (C) 2018

__Behaviours:__ [`gen_server`](gen_server.md).

__Authors:__ yan.guiborat.

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#send-1">send/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td>
Starts the server.</td></tr><tr><td valign="top"><a href="#stop-0">stop/0</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="send-1"></a>

### send/1 ###

<pre><code>
send(Data::tuple()) -&gt; tuple()
</code></pre>
<br />

<a name="start_link-2"></a>

### start_link/2 ###

<pre><code>
start_link(FCMConfig::#{}, NbWorkers::integer()) -&gt; {ok, Pid::pid()} | ignore | {error, Reason::term()}
</code></pre>
<br />

Starts the server

<a name="stop-0"></a>

### stop/0 ###

`stop() -> any()`

