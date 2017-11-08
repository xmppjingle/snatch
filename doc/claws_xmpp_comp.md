

# Module claws_xmpp_comp #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`claws`](claws.md), [`gen_statem`](gen_statem.md).

<a name="types"></a>

## Data Types ##




### <a name="type-state_data">state_data()</a> ###


<pre><code>
state_data() = #data{domain = binary(), password = binary(), host = <a href="inet.md#type-socket_address">inet:socket_address()</a>, port = <a href="inet.md#type-port_number">inet:port_number()</a>, socket = <a href="gen_tcp.md#type-socket">gen_tcp:socket()</a>, trimmed = boolean(), adjust_attrs = boolean(), stream = any()}
</code></pre>




### <a name="type-xmpp_conn_state">xmpp_conn_state()</a> ###


<pre><code>
xmpp_conn_state() = disconnected | retrying | connected | stream_init | authenticate | ready
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#send-2">send/2</a></td><td></td></tr><tr><td valign="top"><a href="#send-3">send/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-3">terminate/3</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="init-1"></a>

### init/1 ###

<pre><code>
init(Params::#{}) -&gt; {ok, <a href="#type-xmpp_conn_state">xmpp_conn_state()</a>, <a href="#type-state_data">state_data()</a>}
</code></pre>
<br />

<a name="send-2"></a>

### send/2 ###

`send(Data, JID) -> any()`

<a name="send-3"></a>

### send/3 ###

`send(Data, JID, ID) -> any()`

<a name="start_link-1"></a>

### start_link/1 ###

<pre><code>
start_link(Params::#{}) -&gt; {ok, pid()}
</code></pre>
<br />

<a name="start_link-2"></a>

### start_link/2 ###

<pre><code>
start_link(Name::atom(), Params::#{}) -&gt; {ok, pid()}
</code></pre>
<br />

<a name="terminate-3"></a>

### terminate/3 ###

`terminate(Reason, StateName, StateData) -> any()`

