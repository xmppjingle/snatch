#!/bin/bash

export KAFKA_VERSION="2.11-1.0.0"
export KAFKA_URL="http://apache.proserve.nl/kafka/1.0.0/kafka_$KAFKA_VERSION.tgz"

apt-get install -y tmux wget \
                        default-jdk \
                        net-tools \
                        build-essential \
                        psmisc

wget -O kafka.tgz $KAFKA_URL
tar xzf kafka.tgz
cd kafka_$KAFKA_VERSION
bin/zookeeper-server-start.sh config/zookeeper.properties &
sleep 1
bin/kafka-server-start.sh config/server.properties &
sleep 5

cd ..
mv kafka_$KAFKA_VERSION /tmp/kafka
