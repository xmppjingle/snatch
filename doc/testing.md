Functional Testing
==================

The better way to perform tests for XMPP using snatch is using the XML syntax to create a set of tests based on steps, actions and checks.

The functional testing for snatch is as follow:

```xml
<functional>
    <config>
        <snatch module="snatch_fun_test_tests"/>
    </config>

    <steps>
        <step name="ping">
            <vars>
                <value key="id">test_bot</value>
                <value key="user">bob@localhost/pc</value>
                <value key="component">alice.localhost</value>
            </vars>
            <send>
                <iq type="get"
                    from="{{user}}"
                    to="{{component}}"
                    id="{{id}}">
                    <ping xmlns="urn:xmpp:ping"/>
                </iq>
            </send>
            <expected>
                <iq type="result"
                    to="{{user}}"
                    from="{{component}}"
                    id="{{id}}"/>
            </expected>
        </step>
    </steps>
</functional>
```

The test gives you information about what snatch module will be in use (this case we used `snatch_fun_test_tests` because this is retrieved from the snatch tests suite).

Note that if you want to start your own process to receive the events instead of the implementation of the *snatch* behaviour, you can configure the *snatch* section in this way:

```xml
<config>
    <snatch router="my_router"/>
</config>
```

The name in use (`my_router` in this example) should be a registered name for the process in charge to receive all of the events.

The next section is `steps`. You can defined as many steps as you need. In this example we defined only one step. Inside we have diferent parts:

- `vars`: let us to define a dictionary. This information could be used in the rest of the sections thru the `{{...}}` syntax.
- `send`: the set of stanzas to be sent to your code. This is intended to be sent from the XMPP server to your code so, you'll receive this via `handle_info` functions. You can define as many stanzas as you want in this section, all of them will be sent at once.
- `expected`: the set of stanzas expected. Your code could generate a response. These responses could be checked with this section. You can include all of the possible stanzas received here. The order is not important.

Another more complete example:

```xml
<functional>
    <config>
        <snatch module="snatch_fun_test_tests"/>
    </config>

    <steps>
        <step name="custom query">
            <vars>
                <value key="id">test_bot</value>
                <value key="user">bob@localhost/pc</value>
                <value key="component">alice.localhost</value>
            </vars>
            <send via="true">
                <iq type="get"
                    from="{{user}}"
                    to="{{component}}"
                    id="{{id}}">
                    <query xmlns="urn:custom"/>
                </iq>
            </send>
            <expected>
                <iq type="result"
                    to="{{user}}"
                    from="{{component}}"
                    id="{{id}}">
                    <query xmlns="urn:custom">
                        <item>{{data}}</item>
                    </query>
                </iq>
            </expected>
            <check module="snatch_fun_test_tests" function="check_data"/>
        </step>
    </steps>
</functional>
```

This example adds two new elements, the possibility to retrieve new information from the expected stanza (`{{data}}`) and the `check` section.

We are going to see more in depth each of these sections.

Vars
----

As we told above, the `vars` section let us to define a dictionary. This is very useful to avoid to repeat again and again some chunks parts of the XML content.

Note that the value could contains only text, tags are not allowed here or could be behave in a non-controlled way.

In the previous examples we used this dictionary to avoid to duplicate the names of the user, componente and ID for the stanzas. But also this dictionary could store new information from the `expected` section as we told before.

The idea is the same as the Erlang variables. If the data exists in the dictionary it's replaced with the previous information. If the data isn't previously in the dictionary then it's binded to the new information arriving on that position.

Send
----

This section let us to send XMPP stanzas or CDATA content. This simulates the interaction from the XMPP Server to the component we're developing. It's the normal interaction. But we can even simulate when we are receiving information from other claws like REST or Kafka.

When we receive a stanza, it's translated to `#xmlel{}` record and passed to the `handle_info/2` functions implemented in your code. The configuration should be done in the first part of the document (in the `config` section). But if the information isn't a XML stanza then we receive the binary as is.

The code could reply to that code or not. That depends on your implementation. You can check if everything went well checking the response in case of this is sent back (using `snatch:send/2-3`) or checking internally your system. See `check` section below for more information about this.

Send has an optional attribute called `via`. This attribute let you to decide if the send for `handle_info/2` implementation from *snatch* should use the send `{received, #xmlel{}}` or `{received, #xmlel{}, #via{}}` instead, depending on if `via` is `false` or `true` respectively.

We can also use `type` (another optional attribute). This attribute is configured by default as `xml` and then the internal process as explained above in this section is applied. But if we use `json` or `raw` the content is passed as binary. This is useful when we want to send or expect for information like it was received by kafka or other claws.

Expected
--------

The expected section is intended to check the expected stanzas after a sent is performed. All of the stanzas in the expected tag should arrive, no matter the order.

If one stanza arrives and it's not expected or one expected stanza doesn't arrive an error is triggered and the tests are aborted.

Expected has the attribute `type` same as `send` tag. The default value is `xml` and we can specify `json` or `raw` to get a binary instead.

Check
-----

The check section let you to define a module and a function. You can implement a function with three params to check the status of the step at some specific moment.

For example:

```erlang
check_data([#xmlel{}], [#xmlel{}], Map) ->
    ?assertMatch(#{ <<"data">> := <<"abc">> }, Map),
    ok.
```

Note that the stanzas received and expected could be binaries as well.

The function implemented will receive three params:

- *Expected Stanzas*. These are the expected stanzas (if there were expected section(s) above). If there were not previous `expected` sections this will be an empty list.

- *Received Stanzas*. The stanzas sent by your system at the moment.

- *Dictionary*. The dictionary (as a `map`) with all of the information retrieve at that moment.

Sections
--------

As I said the sections has no a fixed order. For example, if when you are starting your system it's sending something, then it's a good idea start with an expected section and then maybe a check or even send.

You can add as many `expected`, `send` and `check` sections as you want. The only exection is `vars`.

So, for example, if you want to perform a check or running a specific code, then expect for some stanza, send, check again and then expect for the last stanzas you can proceed in this way:

```xml
<step name="birthday service">
    <check module="birthday_tests" function="launch_system"/>
    <expected>
        <iq type="set" .../>
        <message .../>
    </expected>
    <send>
        <message .../>
    </send>
    <check module="birthday_tests" function="check_messages"/>
    <expected>
        <iq type="get".../>
    </expected>
</step>
```

Using binaries we can see an example as follow:

```xml
<step name="birthday service">
    <check module="birthday_tests" function="launch_system"/>
    <expected><![CDATA[{"get": "birthday"}]]></expected>
    <send><![CDATA[{"result": "tomorrow"}]]></send>
</step>
```

Don't hesitate to comment if this information isn't clear or you need help with this.

Enjoy!
