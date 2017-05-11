#lp_claws:start_link(#{url => "http://35.166.81.153:81/default/eventhandlers/5a1dcb6b-7be0-4cac-b014-4595d41d7f76?appid=app", listener => self()}).
#-eval "application:start(inets). lp_claws:start_link(#{url => \"http://35.166.81.153:81/default/eventhandlers/5a1dcb6b-7be0-4cac-b014-4595d41d7f76?appid=app\", listener => self()})."
erl -pa ebin/ -pa deps/xmpp/ebin/ -pa deps/fast_xml/ebin/ -pa deps/stringprep/ebin/ -pa deps/p1_utils/ebin/ -pa deps/lager/ebin -pa deps/cowboy/ebin -eval "application:start(inets)"
