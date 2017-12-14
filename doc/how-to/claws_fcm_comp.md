Claws FCM Component
====================

This claw is designed to connect to Google FCm servers and provide push functionalities.


This claw should be started as follow:

```erlang
Params = #{
                         gcs_add => "fcm-xmpp.googleapis.com",
                         gcs_port => 5236,
                         server_id => <<"server_id">>,
                         server_key => <<"server_token">>}},

{ok, PID} = claws_fcm_comp:start_link(Params).
```

To effectively connect to the google servers you have to call to the function:

```erlang
claws_fcm_comp:connect().
```

The params passed inside of the map for the `start_link/1` function are:

- `gcs_add` the address of the google FCm server used.
- `gcs_port` an integer for the number of port to be connected.
- `server_id` The server id as given into the firebase console.
- `server_key` The server Token as given by firebase console.

The claw is following different states to perform the connection. The claw is automatically performing this activity in a simple and fast way:

- *Disconnected* is the init state. When the event `connect` is received then it moves to the *Connected* state if the connection is successful or to the *Retrying* state otherwise.
- *Retrying* is the state where the connection stays for 3 seconds until it tries to connect again.
- *Connected* is in charge of create the *fast XML* flow and moves to *Stream Init* state to continue.
- *Stream Init* sends the stream initiation to the server. When receives information from the server it moves to *Authenticate* state. The stream is checked to get the ID to perform the authetication. If the ID isn't there an error happens and the connection is restarted (closed and opened again in *Retrying* state).
- *Authenticate* sends the *handshake* information to the server. It moves to *Ready* state if the returns from the server was correct, crash otherwise.
- *Ready* is kept to handle the incoming and outgoing information. The information arrived from the connection is sent to snatch to be redirected using `snatch:received/2` function. The information sent by the specific implementation is sent directly to the socket (Note that this information MUST be in XML format).

If an event about TCP error or closed is received the state is moved directly to *Retrying*. This way the claw can try to connect again to the server.
