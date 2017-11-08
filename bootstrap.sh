#!/bin/bash

KAFKA_VERSION="2.11-0.11.0.1"

apt-get install -y tmux wget \
                        default-jdk \
                        net-tools \
                        build-essential \
                        psmisc

wget http://apache.cs.uu.nl/kafka/0.11.0.1/kafka_$KAFKA_VERSION.tgz
tar xzf kafka_$KAFKA_VERSION.tgz
cd kafka_$KAFKA_VERSION
bin/zookeeper-server-start.sh config/zookeeper.properties &
sleep 1
bin/kafka-server-start.sh config/server.properties &
sleep 5

export KAFKA_DIR="$(pwd)/kafka_$KAFKA_VERSION"
