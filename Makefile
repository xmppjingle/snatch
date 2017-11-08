all: compile

doc:
	./rebar3 as doc edown

clean-devel: clean
	-rm -rf _build

clean:
	./rebar3 clean

compile:
	./rebar3 compile

kafka:
	${KAFKA_DIR}/bin/zookeeper-server-start.sh ${KAFKA_DIR}/config/zookeeper.properties &
	sleep 1
	${KAFKA_DIR}/bin/kafka-server-start.sh ${KAFKA_DIR}/config/server.properties &
	sleep 5
	${KAFKA_DIR}/bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic xmpp.in
	${KAFKA_DIR}/bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic xmpp.out

test: teardown kafka eunit teardown

teardown:
	-killall -9 java
	-rm -rf /tmp/kafka-logs
	-rm -rf /tmp/zookeeper

eunit:
	-epmd -daemon
	./rebar3 do xref, eunit, cover
	./covertool \
		-cover _build/test/cover/eunit.coverdata \
		-appname snatch \
		-output cobertura.xml > /dev/null

shell:
	./rebar3 shell

.PHONY: doc test compile all shell kafka teardown eunit
