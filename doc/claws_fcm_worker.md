

# Module claws_fcm_worker #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_statem`](gen_statem.md).

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#authenticate-3">authenticate/3</a></td><td></td></tr><tr><td valign="top"><a href="#bind-3">bind/3</a></td><td></td></tr><tr><td valign="top"><a href="#binded-3">binded/3</a></td><td></td></tr><tr><td valign="top"><a href="#binding-3">binding/3</a></td><td></td></tr><tr><td valign="top"><a href="#callback_mode-0">callback_mode/0</a></td><td></td></tr><tr><td valign="top"><a href="#code_change-4">code_change/4</a></td><td></td></tr><tr><td valign="top"><a href="#connect-0">connect/0</a></td><td></td></tr><tr><td valign="top"><a href="#connected-3">connected/3</a></td><td></td></tr><tr><td valign="top"><a href="#disconnect-0">disconnect/0</a></td><td></td></tr><tr><td valign="top"><a href="#disconnected-3">disconnected/3</a></td><td></td></tr><tr><td valign="top"><a href="#drainned-3">drainned/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_event-4">handle_event/4</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#retrying-3">retrying/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#stream_init-3">stream_init/3</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-3">terminate/3</a></td><td></td></tr><tr><td valign="top"><a href="#wait_for_binding-3">wait_for_binding/3</a></td><td></td></tr><tr><td valign="top"><a href="#wait_for_features-3">wait_for_features/3</a></td><td></td></tr><tr><td valign="top"><a href="#wait_for_result-3">wait_for_result/3</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="authenticate-3"></a>

### authenticate/3 ###

`authenticate(X1, X2, Data) -> any()`

<a name="bind-3"></a>

### bind/3 ###

`bind(X1, X2, Data) -> any()`

<a name="binded-3"></a>

### binded/3 ###

`binded(Typ, Unknown, Data) -> any()`

<a name="binding-3"></a>

### binding/3 ###

`binding(X1, X2, Data) -> any()`

<a name="callback_mode-0"></a>

### callback_mode/0 ###

`callback_mode() -> any()`

<a name="code_change-4"></a>

### code_change/4 ###

`code_change(OldVsn, State, Data, Extra) -> any()`

<a name="connect-0"></a>

### connect/0 ###

`connect() -> any()`

<a name="connected-3"></a>

### connected/3 ###

`connected(X1, X2, Data) -> any()`

<a name="disconnect-0"></a>

### disconnect/0 ###

`disconnect() -> any()`

<a name="disconnected-3"></a>

### disconnected/3 ###

`disconnected(Type, X2, Data) -> any()`

<a name="drainned-3"></a>

### drainned/3 ###

`drainned(X1, Msg, Data) -> any()`

<a name="handle_event-4"></a>

### handle_event/4 ###

`handle_event(Type, Content, State, Data) -> any()`

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`

<a name="retrying-3"></a>

### retrying/3 ###

`retrying(X1, X2, Data) -> any()`

<a name="start_link-1"></a>

### start_link/1 ###

`start_link(FCMParams) -> any()`

<a name="stream_init-3"></a>

### stream_init/3 ###

`stream_init(X1, X2, Data) -> any()`

<a name="terminate-3"></a>

### terminate/3 ###

`terminate(Reason, StateName, StateData) -> any()`

<a name="wait_for_binding-3"></a>

### wait_for_binding/3 ###

`wait_for_binding(X1, X2, Data) -> any()`

<a name="wait_for_features-3"></a>

### wait_for_features/3 ###

`wait_for_features(X1, X2, Data) -> any()`

<a name="wait_for_result-3"></a>

### wait_for_result/3 ###

`wait_for_result(X1, X2, Data) -> any()`

