#!/bin/bash

# Copyright 2014 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
CONF_DIR=/etc/cassandra
CFG=$CONF_DIR/cassandra.yaml
REPORT_CFG=$CONF_DIR/reporting.yaml

# we are doing PetSet or just setting our seeds
if [ -z "$CASSANDRA_SEEDS" ]; then
  HOSTNAME=$(hostname -f)
fi

# The following vars relate to there counter parts in $CFG
# for instance rpc_address
CASSANDRA_RPC_ADDRESS="${CASSANDRA_RPC_ADDRESS:-0.0.0.0}"
CASSANDRA_NUM_TOKENS="${CASSANDRA_NUM_TOKENS:-32}"
CASSANDRA_CLUSTER_NAME="${CASSANDRA_CLUSTER_NAME:='Test Cluster'}"
CASSANDRA_LISTEN_ADDRESS=${POD_IP:-$HOSTNAME}
CASSANDRA_BROADCAST_ADDRESS=${POD_IP:-$HOSTNAME}
CASSANDRA_BROADCAST_RPC_ADDRESS=${POD_IP:-$HOSTNAME}
CASSANDRA_MIGRATION_WAIT="${CASSANDRA_MIGRATION_WAIT:-1}"
CASSANDRA_ENDPOINT_SNITCH="${CASSANDRA_ENDPOINT_SNITCH:-SimpleSnitch}"
CASSANDRA_DC="${CASSANDRA_DC}"
CASSANDRA_RACK="${CASSANDRA_RACK}"
CASSANDRA_RING_DELAY="${CASSANDRA_RING_DELAY:-30000}"
CASSANDRA_AUTO_BOOTSTRAP="${CASSANDRA_AUTO_BOOTSTRAP:-true}"
CASSANDRA_SEEDS="${CASSANDRA_SEEDS:false}"
CASSANDRA_REPORT_PORT=2003

# Turn off JMX auth
CASSANDRA_OPEN_JMX="${CASSANDRA_OPEN_JMX:-false}"
# send GC to STDOUT
CASSANDRA_GC_STDOUT="${CASSANDRA_GC_STDOUT:-false}"

# TODO: Get rack and dc working
# Eventually do snitch $DC $RACK?
# $DC based on yaml.  Two racks in a DC??
# can use node selectors to put
# Eventualy code a snitch that talks to the api to get the labels from the nodes
# Not sure how to do the SeedProviders, either run seperate services or launch a Seed node
# in every DC. Probably need seperate services and capabilty to set ips based on ENV vars?
# GoogleProvider sets region as DC and Zone as rack
# https://github.com/apache/cassandra/blob/cassandra-3.5/src/java/org/apache/cassandra/locator/GoogleCloudSnitch.java
# GoogleCloudSnitch may work already

if [[ $CASSANDRA_DC && $CASSANDRA_RACK ]]; then
  echo "dc=$CASSANDRA_DC" > $CONF_DIR/cassandra-rackdc.properties
  echo "rack=$CASSANDRA_RACK" >> $CONF_DIR/cassandra-rackdc.properties
  CASSANDRA_ENDPOINT_SNITCH="GossipingPropertyFileSnitch"
fi

# TODO what else needs to be modified
for yaml in \
  broadcast_address \
  broadcast_rpc_address \
  cluster_name \
  listen_address \
  num_tokens \
  rpc_address \
  endpoint_snitch \
; do
  var="CASSANDRA_${yaml^^}"
  val="${!var}"
  if [ "$val" ]; then
    sed -ri 's/^(# )?('"$yaml"':).*/\2 '"$val"'/' "$CFG"
  fi
done

echo "auto_bootstrap: ${CASSANDRA_AUTO_BOOTSTRAP}" >> $CFG

# set the seed to itself.  This is only for the first pod, otherwise
# it will be able to get seeds from the seed provider
if [[ $CASSANDRA_SEEDS == 'false' ]]; then
  sed -ri 's/- seeds:.*/- seeds: "'"$POD_IP"'"/' $CFG
else # if we have seeds set them.  Probably PetSet
  sed -ri 's/- seeds:.*/- seeds: "'"$CASSANDRA_SEEDS"'"/' $CFG
fi

# send gc to stdout
if [[ $CASSANDRA_GC_STDOUT == 'true' ]]; then
  sed -ri 's/ -Xloggc:\/var\/log\/cassandra\/gc\.log//' $CONF_DIR/cassandra-env.sh
fi

# enable RMI and JMX to work on one port
echo "JVM_OPTS=\"\$JVM_OPTS -Djava.rmi.server.hostname=$POD_IP\"" >> $CONF_DIR/cassandra-env.sh

# enable influxdb reporting if needed
if [ ! -z "$CASSANDRA_REPORT_HOST" ]; then
    echo "JVM_OPTS=\"\$JVM_OPTS -Dcassandra.metricsReporterConfigFile=${REPORT_CFG}\"" >> $CONF_DIR/cassandra-env.sh
    CLASS_PATH=${CLASS_PATH}:/usr/share/cassandra/lib/metrics-graphite-2.2.0.jar:/usr/share/cassandra/lib/metrics-core-2.2.0.jar
    cat > $REPORT_CFG <<EOF
graphite:
-
  period: 20
  timeunit: 'SECONDS'
  prefix: '${HOSTNAME}'
  hosts:
  - host: '${CASSANDRA_REPORT_HOST}'
    port: ${CASSANDRA_REPORT_PORT}
  predicate:
    color: "white"
    useQualifiedName: false
    patterns:
    - ".*"
EOF
fi


# getting WARNING messages with Migration Service
echo "-Dcassandra.migration_task_wait_in_seconds=${CASSANDRA_MIGRATION_WAIT}" >> $CONF_DIR/jvm.options
echo "-Dcassandra.ring_delay_ms=${CASSANDRA_RING_DELAY}" >> $CONF_DIR/jvm.options


if [[ $CASSANDRA_OPEN_JMX == 'true' ]]; then
  export LOCAL_JMX=no
  sed -ri 's/ -Dcom\.sun\.management\.jmxremote\.authenticate=true/ -Dcom\.sun\.management\.jmxremote\.authenticate=false/' $CONF_DIR/cassandra-env.sh
  sed -ri 's/ -Dcom\.sun\.management\.jmxremote\.password\.file=\/etc\/cassandra\/jmxremote\.password//' $CONF_DIR/cassandra-env.sh
fi

echo Starting Cassandra on ${CASSANDRA_LISTEN_ADDRESS}
echo CASSANDRA_RPC_ADDRESS ${CASSANDRA_RPC_ADDRESS}
echo CASSANDRA_NUM_TOKENS ${CASSANDRA_NUM_TOKENS}
echo CASSANDRA_CLUSTER_NAME ${CASSANDRA_CLUSTER_NAME}
echo CASSANDRA_LISTEN_ADDRESS ${CASSANDRA_LISTEN_ADDRESS}
echo CASSANDRA_BROADCAST_ADDRESS ${CASSANDRA_BROADCAST_ADDRESS}
echo CASSANDRA_BROADCAST_RPC_ADDRESS ${CASSANDRA_BROADCAST_RPC_ADDRESS}
echo CASSANDRA_MIGRATION_WAIT ${CASSANDRA_MIGRATION_WAIT}
echo CASSANDRA_ENDPOINT_SNITCH ${CASSANDRA_ENDPOINT_SNITCH}
echo CASSANDRA_DC ${CASSANDRA_DC}
echo CASSANDRA_RACK ${CASSANDRA_RACK}
echo CASSANDRA_RING_DELAY ${CASSANDRA_RING_DELAY}
echo CASSANDRA_AUTO_BOOTSTRAP ${CASSANDRA_AUTO_BOOTSTRAP}
echo CASSANDRA_SEEDS ${CASSANDRA_SEEDS}

export CLASS_PATH=$CLASS_PATH
cassandra -f
