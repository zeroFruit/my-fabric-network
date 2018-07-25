#!/bin/bash

SDIR=$(dirname "$0")
source $SDIR/scripts/env.sh

function main {
   {
   writeHeader
   writeRootFabricCA
   if $USE_INTERMEDIATE_CA; then
      writeIntermediateFabricCA
   fi
   writeSetupFabric
   writeStartFabric
   } > $SDIR/docker-compose.yaml
   log "Created docker-compose.yaml"
}

function writeHeader {
   echo "version: '2'

networks:
  $NETWORK:

services:
"
}

# Write services for the root fabric CA servers
function writeRootFabricCA {
   for ORG in $ORGS; do
      initOrgVars $ORG
      writeRootCA
   done
}

function writeRootCA {
   echo "  $ROOT_CA_NAME:
    container_name: $ROOT_CA_NAME
    image: hyperledger/fabric-ca
    command: /bin/bash -c '/scripts/start-root-ca.sh 2>&1 | tee /$ROOT_CA_LOGFILE'
    environment:
      - FABRIC_CA_SERVER_HOME=/etc/hyperledger/fabric-ca
      - FABRIC_CA_SERVER_TLS_ENABLED=true
      - FABRIC_CA_SERVER_CSR_CN=$ROOT_CA_NAME
      - FABRIC_CA_SERVER_CSR_HOSTS=$ROOT_CA_HOST
      - FABRIC_CA_SERVER_DEBUG=true
      - BOOTSTRAP_USER_PASS=$ROOT_CA_ADMIN_USER_PASS
      - TARGET_CERTFILE=$ROOT_CA_CERTFILE
      - FABRIC_ORGS="$ORGS"
    volumes:
      - ./scripts:/scripts
      - ./$DATA:/$DATA
    networks:
      - $NETWORK
"
}

# Write services for the intermediate fabric CA servers
function writeIntermediateFabricCA {
   for ORG in $ORGS; do
      initOrgVars $ORG
      writeIntermediateCA
   done
}

function writeIntermediateCA {
   echo "  $INT_CA_NAME:
    container_name: $INT_CA_NAME
    image: hyperledger/fabric-ca
    command: /bin/bash -c '/scripts/start-intermediate-ca.sh $ORG 2>&1 | tee /$INT_CA_LOGFILE'
    environment:
      - FABRIC_CA_SERVER_HOME=/etc/hyperledger/fabric-ca
      - FABRIC_CA_SERVER_CA_NAME=$INT_CA_NAME
      - FABRIC_CA_SERVER_INTERMEDIATE_TLS_CERTFILES=$ROOT_CA_CERTFILE
      - FABRIC_CA_SERVER_CSR_HOSTS=$INT_CA_HOST
      - FABRIC_CA_SERVER_TLS_ENABLED=true
      - FABRIC_CA_SERVER_DEBUG=true
      - BOOTSTRAP_USER_PASS=$INT_CA_ADMIN_USER_PASS
      - PARENT_URL=https://$ROOT_CA_ADMIN_USER_PASS@$ROOT_CA_HOST:7054
      - TARGET_CHAINFILE=$INT_CA_CHAINFILE
      - ORG=$ORG
      - FABRIC_ORGS="$ORGS"
    volumes:
      - ./scripts:/scripts
      - ./$DATA:/$DATA
    networks:
      - $NETWORK
    depends_on:
      - $ROOT_CA_NAME
"
}

# Write a service to setup the fabric artifacts (e.g. genesis block, etc)
function writeSetupFabric {
   echo "  setup:
    container_name: setup
    image: hyperledger/fabric-ca-tools
    command: /bin/bash -c '/scripts/setup-fabric.sh 2>&1 | tee /$SETUP_LOGFILE; sleep 99999'
    volumes:
      - ./scripts:/scripts
      - ./$DATA:/$DATA
    networks:
      - $NETWORK
    depends_on:"
   for ORG in $ORGS; do
      initOrgVars $ORG
      echo "      - $CA_NAME"
   done

   for kafka_org in $KAFKA_ORGS; do
        count=1
        while [[ "$count" -le $NUM_KAFKAS ]]; do
            initKafkaVars $kafka_org $count
            echo "      - $KAFKA_NAME"
            count=$((count+1))
        done
   done
   echo ""
}

# Write services for fabric orderer and peer containers
function writeStartFabric {
   for ORDERER_ORG in $ORDERER_ORGS; do
      COUNT=1
      while [[ "$COUNT" -le $NUM_ORDERERS ]]; do
         initOrdererVars $ORDERER_ORG $COUNT
         writeOrderer $COUNT
         COUNT=$((COUNT+1))
      done
   done

   for ORG in $PEER_ORGS; do
      COUNT=1
      while [[ "$COUNT" -le $NUM_PEERS ]]; do
         initPeerVars $ORG $COUNT
         writePeer
         COUNT=$((COUNT+1))
      done
   done

   if test "$ORDERER_MODE" = "kafka"; then
        writeZookeeperList
        writeKafkaList
   fi
}

function writeOrderer {
   MYHOME=/etc/hyperledger/orderer
   NUM=$1
   let port="1000 * ($NUM - 1) + 7050"

   echo "  $ORDERER_NAME:
    container_name: $ORDERER_NAME
    image: hyperledger/fabric-ca-orderer
    environment:
      - FABRIC_CA_CLIENT_HOME=$MYHOME
      - FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
      - ENROLLMENT_URL=https://$ORDERER_NAME_PASS@$CA_HOST:7054
      - ORDERER_HOME=$MYHOME
      - ORDERER_HOST=$ORDERER_HOST
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_GENESISMETHOD=file
      - ORDERER_GENERAL_GENESISFILE=$GENESIS_BLOCK_FILE
      - ORDERER_GENERAL_LOCALMSPID=$ORG_MSP_ID
      - ORDERER_GENERAL_LOCALMSPDIR=$MYHOME/msp
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=$MYHOME/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=$MYHOME/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[$CA_CHAINFILE]
      - ORDERER_GENERAL_TLS_CLIENTAUTHREQUIRED=true
      - ORDERER_GENERAL_TLS_CLIENTROOTCAS=[$CA_CHAINFILE]
      - ORDERER_GENERAL_LOGLEVEL=debug
      - ORDERER_DEBUG_BROADCASTTRACEDIR=$LOGDIR
      - ORG=$ORG
      - ORG_ADMIN_CERT=$ORG_ADMIN_CERT
    command: /bin/bash -c '/scripts/start-orderer.sh 2>&1 | tee /$ORDERER_LOGFILE'
    volumes:
      - ./scripts:/scripts
      - ./$DATA:/$DATA
    networks:
      - $NETWORK
    depends_on:
      - setup"

    for kafka_org in $KAFKA_ORGS; do
        local count=1
        while [[ "$count" -le $NUM_KAFKAS ]]; do
            initKafkaVars $kafka_org $count
            echo "      - $KAFKA_NAME"
            count=$((count+1))
        done
    done

    echo "    ports:
      - $port:7050
"
}

function writePeer {
   MYHOME=/opt/gopath/src/github.com/hyperledger/fabric/peer
   echo "  $PEER_NAME:
    container_name: $PEER_NAME
    image: hyperledger/fabric-ca-peer
    environment:
      - FABRIC_CA_CLIENT_HOME=$MYHOME
      - FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
      - ENROLLMENT_URL=https://$PEER_NAME_PASS@$CA_HOST:7054
      - PEER_NAME=$PEER_NAME
      - PEER_HOME=$MYHOME
      - PEER_HOST=$PEER_HOST
      - PEER_NAME_PASS=$PEER_NAME_PASS
      - CORE_PEER_ID=$PEER_HOST
      - CORE_PEER_ADDRESS=$PEER_HOST:7051
      - CORE_PEER_LOCALMSPID=$ORG_MSP_ID
      - CORE_PEER_MSPCONFIGPATH=$MYHOME/msp
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=net_${NETWORK}
      - CORE_LOGGING_LEVEL=DEBUG
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=$MYHOME/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=$MYHOME/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=$CA_CHAINFILE
      - CORE_PEER_TLS_CLIENTAUTHREQUIRED=true
      - CORE_PEER_TLS_CLIENTROOTCAS_FILES=$CA_CHAINFILE
      - CORE_PEER_TLS_CLIENTCERT_FILE=/$DATA/tls/$PEER_NAME-client.crt
      - CORE_PEER_TLS_CLIENTKEY_FILE=/$DATA/tls/$PEER_NAME-client.key
      - CORE_PEER_GOSSIP_USELEADERELECTION=true
      - CORE_PEER_GOSSIP_ORGLEADER=false
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=$PEER_HOST:7051
      - CORE_PEER_GOSSIP_SKIPHANDSHAKE=true
      - ORG=$ORG
      - ORG_ADMIN_CERT=$ORG_ADMIN_CERT"
   if [ $NUM -gt 1 ]; then
      echo "      - CORE_PEER_GOSSIP_BOOTSTRAP=peer1-${ORG}:7051"
   fi
   echo "    working_dir: $MYHOME
    command: /bin/bash -c '/scripts/start-peer.sh 2>&1 | tee /$PEER_LOGFILE'
    volumes:
      - ./scripts:/scripts
      - ./$DATA:/$DATA
      - /var/run:/host/var/run
    networks:
      - $NETWORK
    depends_on:
      - setup
"
}

function writeZookeeperList {
    for zookeeper_org in $ZOOKEEPER_ORGS; do
        local count=1
        while [[ "$count" -le $NUM_ZOOKEEPERS ]]; do
            writeZookeeper $zookeeper_org $count
            count=$(($count+1))
        done
    done

}

function writeZookeeper {
    local org=$1
    local num=$2

    makeZooServersEnv
    initZookeeperVars $org $num

    echo "  $ZOOKEEPER_NAME:
    container_name: $ZOOKEEPER_NAME
    image: hyperledger/fabric-zookeeper
    environment:
      - ZOO_SERVERS=$ZOO_SERVERS
      - ZOO_MY_ID=$num
    restart: always
    ports:
      - $(( ($num-1) * 10000 + 2181 )):2181
      - $(( ($num-1) * 10000 + 2888 )):2888
      - $(( ($num-1) * 10000 + 3888 )):3888
    networks:
      - my-network
    "
}

function makeZooServersEnv {
    ZOO_SERVERS=""

    for ZOOKEEPER_ORG in $ZOOKEEPER_ORGS; do
        initZookeeperVars $ZOOKEEPER_ORG 1
        ZOO_SERVERS="server.$count=$ZOOKEEPER_NAME:$ZOOKEEPER_FOLLOWER_PORT:$ZOOKEEPER_ELECTION_PORT"

        local count=2
        while [[ "$count" -le $NUM_ZOOKEEPERS ]]; do
            initZookeeperVars $ZOOKEEPER_ORG $count
            ZOO_SERVERS="$ZOO_SERVERS server.$count=$ZOOKEEPER_NAME:$ZOOKEEPER_FOLLOWER_PORT:$ZOOKEEPER_ELECTION_PORT"
            count=$((count+1))
        done
    done
    read -rd '' ZOO_SERVERS <<< "$ZOO_SERVERS"

}

function writeKafkaList {
    for kafka_org in $KAFKA_ORGS; do
        local count=1
        while [[ "$count" -le $NUM_KAFKAS ]]; do
            writeKafka $kafka_org $count
            count=$((count+1))
        done
    done

}

function writeKafka {
    local org=$1
    local num=$2

    initKafkaVars $org $num

    echo "  $KAFKA_NAME:
    container_name: $KAFKA_NAME
    image: hyperledger/fabric-kafka
    environment:
      - KAFKA_BROKER_ID=$((num-1))
      - KAFKA_MESSAGE_MAX_BYTES=$KAFKA_MESSAGE_MAX_BYTES
      - KAFKA_REPLICA_FETCH_MAX_BYTES=$KAFKA_REPLICA_FETCH_MAX_BYTES
      - KAFKA_UNCLEAN_LEADER_ELECTION_ENABLE=$KAFKA_UNCLEAN_LEADER_ELECTION_ENABLE
      - KAFKA_MIN_INSYNC_REPLICAS=$KAFKA_MIN_INSYNC_REPLICAS
      - KAFKA_DEFAULT_REPLICATION_FACTOR=$KAFKA_DEFAULT_REPLICATION_FACTOR
      - KAFKA_ZOOKEEPER_CONNECT=$KAFKA_ZOOKEEPER_CONNECT
    ports:
      - $(( ($num-1) * 10000 + 9092 )):9092
      - $(( ($num-1) * 10000 + 9093 )):9093
    depends_on:"

    for zookeeper_org in $ZOOKEEPER_ORGS; do
        local count=1
        while [[ "$count" -le $NUM_ZOOKEEPERS ]]; do
            initZookeeperVars $zookeeper_org $count
            echo "      - $ZOOKEEPER_NAME"
            count=$((count+1))
        done
    done
    echo "    networks:
      - $NETWORK
    "

}

main
