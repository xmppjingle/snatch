#!/bin/bash

apt-get install -y tmux wget default-jdk net-tools build-essential

wget http://apache.cs.uu.nl/kafka/0.11.0.1/kafka_2.11-0.11.0.1.tgz
tar xzf kafka_2.11-0.11.0.1.tgz
cd kafka_2.11-0.11.0.1
tmux new -d bin/zookeeper-server-start.sh config/zookeeper.properties
sleep 1
tmux new -d bin/kafka-server-start.sh config/server.properties
sleep 5
bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic xmpp.in
bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic xmpp.out
