#application:start(lager), lager:set_loglevel(lager_console_backend, debug), application:start(xmpp), xmpp_claws:start_link(["localhost", 5222, <<"me">>, <<"localhost">>, <<"password">>, <<"R">>, self()]), xmpp_claws:connect().

erl -pa ebin/ -pa deps/xmpp/ebin/ -pa deps/fast_xml/ebin/ -pa deps/stringprep/ebin/ -pa deps/p1_utils/ebin/ -pa deps/lager/ebin
