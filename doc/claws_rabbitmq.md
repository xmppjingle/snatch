

# Module claws_rabbitmq #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`claws`](claws.md), [`gen_server`](gen_server.md).

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#publish-1">publish/1</a></td><td></td></tr><tr><td valign="top"><a href="#publish-2">publish/2</a></td><td></td></tr><tr><td valign="top"><a href="#register-1">register/1</a></td><td></td></tr><tr><td valign="top"><a href="#send-2">send/2</a></td><td></td></tr><tr><td valign="top"><a href="#send-3">send/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, State, Extra) -> any()`

<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(Request, From, State) -> any()`

<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(Msg, State) -> any()`

<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(Basic.consume_ok, State) -> any()`

<a name="init-1"></a>

### init/1 ###

`init(Opts) -> any()`

<a name="publish-1"></a>

### publish/1 ###

`publish(Data) -> any()`

<a name="publish-2"></a>

### publish/2 ###

`publish(Data, JID) -> any()`

<a name="register-1"></a>

### register/1 ###

`register(SocketConnection) -> any()`

<a name="send-2"></a>

### send/2 ###

`send(Data, JID) -> any()`

<a name="send-3"></a>

### send/3 ###

`send(Data, JID, ID) -> any()`

<a name="start_link-1"></a>

### start_link/1 ###

`start_link(Params) -> any()`

<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State) -> any()`

