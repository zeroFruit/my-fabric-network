#!/bin/bash

# Name of the docker-compose network
NETWORK=my-network

# Names of the orderer organizations
ORDERER_ORGS="org0"
# Number of orderer nodes
NUM_ORDERERS=2

# Names of the peer organizations
PEER_ORGS="org1 org2"
# Number of peers in each peer organization
NUM_PEERS=2

ZOOKEEPER_ORGS="org0"
NUM_ZOOKEEPERS=3
ZOOKEEPER_FOLLOWER_PORT=2888
ZOOKEEPER_ELECTION_PORT=3888

KAFKA_ORGS="org0"
NUM_KAFKAS=4

# All org names
ORGS="$ORDERER_ORGS $PEER_ORGS"

# Set to true to populate the "admincerts" folder of MSPs
ADMINCERTS=true

# The volume mount to share data between containers
DATA=data

# The path to the genesis block
GENESIS_BLOCK_FILE=/$DATA/genesis.block

# The path to a channel transaction
CHANNEL_TX_FILE=/$DATA/channel.tx

# Name of test channel
CHANNEL_NAME=mychannel

# Setup timeout in seconds (for setup container to complete)
SETUP_TIMEOUT=120

# Log directory
LOGDIR=$DATA/logs
LOGPATH=/$LOGDIR

# Name of a the file to create when setup is successful
SETUP_SUCCESS_FILE=${LOGDIR}/setup.successful
# The setup container's log file
SETUP_LOGFILE=${LOGDIR}/setup.log

# Set to true to enable use of intermediate CAs
USE_INTERMEDIATE_CA=true

ORDERER_MODE="kafka"


# initOrgVars <ORG>
function initOrgVars {
   if [ $# -ne 1 ]; then
      echo "Usage: initOrgVars <ORG>"
      exit 1
   fi
   ORG=$1
   ORG_CONTAINER_NAME=${ORG//./-}
   ROOT_CA_HOST=rca-${ORG}
   ROOT_CA_NAME=rca-${ORG}
   ROOT_CA_LOGFILE=$LOGDIR/${ROOT_CA_NAME}.log
   INT_CA_HOST=ica-${ORG}
   INT_CA_NAME=ica-${ORG}
   INT_CA_LOGFILE=$LOGDIR/${INT_CA_NAME}.log

   # Root CA admin identity
   ROOT_CA_ADMIN_USER=rca-${ORG}-admin
   ROOT_CA_ADMIN_PASS=${ROOT_CA_ADMIN_USER}pw
   ROOT_CA_ADMIN_USER_PASS=${ROOT_CA_ADMIN_USER}:${ROOT_CA_ADMIN_PASS}
   # Root CA intermediate identity to bootstrap the intermediate CA
   ROOT_CA_INT_USER=ica-${ORG}
   ROOT_CA_INT_PASS=${ROOT_CA_INT_USER}pw
   ROOT_CA_INT_USER_PASS=${ROOT_CA_INT_USER}:${ROOT_CA_INT_PASS}
   # Intermediate CA admin identity
   INT_CA_ADMIN_USER=ica-${ORG}-admin
   INT_CA_ADMIN_PASS=${INT_CA_ADMIN_USER}pw
   INT_CA_ADMIN_USER_PASS=${INT_CA_ADMIN_USER}:${INT_CA_ADMIN_PASS}
   # Admin identity for the org
   ADMIN_NAME=admin-${ORG}
   ADMIN_PASS=${ADMIN_NAME}pw
   # Typical user identity for the org
   USER_NAME=user-${ORG}
   USER_PASS=${USER_NAME}pw

   ROOT_CA_CERTFILE=/${DATA}/${ORG}-ca-cert.pem
   INT_CA_CHAINFILE=/${DATA}/${ORG}-ca-chain.pem
   ANCHOR_TX_FILE=/${DATA}/orgs/${ORG}/anchors.tx
   ORG_MSP_ID=${ORG}MSP
   ORG_MSP_DIR=/${DATA}/orgs/${ORG}/msp
   ORG_ADMIN_CERT=${ORG_MSP_DIR}/admincerts/cert.pem
   ORG_ADMIN_HOME=/${DATA}/orgs/$ORG/admin

   if test "$USE_INTERMEDIATE_CA" = "true"; then
      CA_NAME=$INT_CA_NAME
      CA_HOST=$INT_CA_HOST
      CA_CHAINFILE=$INT_CA_CHAINFILE
      CA_ADMIN_USER_PASS=$INT_CA_ADMIN_USER_PASS
      CA_LOGFILE=$INT_CA_LOGFILE
   else
      CA_NAME=$ROOT_CA_NAME
      CA_HOST=$ROOT_CA_HOST
      CA_CHAINFILE=$ROOT_CA_CERTFILE
      CA_ADMIN_USER_PASS=$ROOT_CA_ADMIN_USER_PASS
      CA_LOGFILE=$ROOT_CA_LOGFILE
   fi
}

# initOrdererVars <NUM>
function initOrdererVars {
   if [ $# -ne 2 ]; then
      echo "Usage: initOrdererVars <ORG> <NUM>"
      exit 1
   fi
   initOrgVars $1
   NUM=$2
   ORDERER_HOST=orderer${NUM}-${ORG}
   ORDERER_NAME=orderer${NUM}-${ORG}
   ORDERER_PASS=${ORDERER_NAME}pw
   ORDERER_NAME_PASS=${ORDERER_NAME}:${ORDERER_PASS}
   ORDERER_LOGFILE=$LOGDIR/${ORDERER_NAME}.log
   MYHOME=/etc/hyperledger/orderer

   export FABRIC_CA_CLIENT=$MYHOME
   export ORDERER_GENERAL_LOGLEVEL=debug
   export ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
   export ORDERER_GENERAL_GENESISMETHOD=file
   export ORDERER_GENERAL_GENESISFILE=$GENESIS_BLOCK_FILE
   export ORDERER_GENERAL_LOCALMSPID=$ORG_MSP_ID
   export ORDERER_GENERAL_LOCALMSPDIR=$MYHOME/msp
   # enabled TLS
   export ORDERER_GENERAL_TLS_ENABLED=true
   TLSDIR=$MYHOME/tls
   export ORDERER_GENERAL_TLS_PRIVATEKEY=$TLSDIR/server.key
   export ORDERER_GENERAL_TLS_CERTIFICATE=$TLSDIR/server.crt
   export ORDERER_GENERAL_TLS_ROOTCAS=[$CA_CHAINFILE]

   if test "$ORDERER_MODE" = "kafka"; then
       export ORDERER_KAFKA_RETRY_SHORTINTERVAL=1s
       export ORDERER_KAFKA_RETRY_SHORTTOTAL=30s
       export ORDERER_KAFKA_VERBOSE=true
   fi

}

function initZookeeperVars {
    local org=$1
    local num=$2

    ZOOKEEPER_HOST=zookeeper${num}-${org}
    ZOOKEEPER_NAME=zookeeper${num}-${org}
    ZOOKEEPER_LOGFILE=$LOGDIR/${ZOOKEEPER_NAME}.log
    MYHOME=/etc/hyperledger/zookeeper
}

function initKafkaVars {
    local org=$1
    local num=$2

    KAFKA_NAME=kafka${num}-${org}
    KAFKA_HOST=kafka${num}-${org}

    KAFKA_MESSAGE_MAX_BYTES=103809024
    KAFKA_REPLICA_FETCH_MAX_BYTES=103809024
    KAFKA_UNCLEAN_LEADER_ELECTION_ENABLE=false
    KAFKA_MIN_INSYNC_REPLICAS=2
    KAFKA_DEFAULT_REPLICATION_FACTOR=3

    for zookeeper_org in $ZOOKEEPER_ORGS; do
        initZookeeperVars $zookeeper_org 1
        KAFKA_ZOOKEEPER_CONNECT="$ZOOKEEPER_HOST:2181"

        local count=2
        while [[ "$count" -le $NUM_ZOOKEEPERS ]]; do
            initZookeeperVars $zookeeper_org $count
            KAFKA_ZOOKEEPER_CONNECT="$KAFKA_ZOOKEEPER_CONNECT,$ZOOKEEPER_HOST:2181"
            count=$((count+1))
        done
    done
    read -rd '' KAFKA_ZOOKEEPER_CONNECT <<< "$KAFKA_ZOOKEEPER_CONNECT"
}


# initPeerVars <ORG> <NUM>
function initPeerVars {
   if [ $# -ne 2 ]; then
      echo "Usage: initPeerVars <ORG> <NUM>: $*"
      exit 1
   fi
   initOrgVars $1
   NUM=$2
   PEER_HOST=peer${NUM}-${ORG}
   PEER_NAME=peer${NUM}-${ORG}
   PEER_PASS=${PEER_NAME}pw
   PEER_NAME_PASS=${PEER_NAME}:${PEER_PASS}
   PEER_LOGFILE=$LOGDIR/${PEER_NAME}.log
   MYHOME=/opt/gopath/src/github.com/hyperledger/fabric/peer
   TLSDIR=$MYHOME/tls

   export FABRIC_CA_CLIENT=$MYHOME
   export CORE_PEER_ID=$PEER_HOST
   export CORE_PEER_ADDRESS=$PEER_HOST:7051
   export CORE_PEER_LOCALMSPID=$ORG_MSP_ID
   export CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
   # the following setting starts chaincode containers on the same
   # bridge network as the peers
   # https://docs.docker.com/compose/networking/
   #export CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=${COMPOSE_PROJECT_NAME}_${NETWORK}
   export CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=net_${NETWORK}
   # export CORE_LOGGING_LEVEL=ERROR
   export CORE_LOGGING_LEVEL=DEBUG
   export CORE_PEER_TLS_ENABLED=true
   export CORE_PEER_TLS_CLIENTAUTHREQUIRED=true
   export CORE_PEER_TLS_ROOTCERT_FILE=$CA_CHAINFILE
   export CORE_PEER_TLS_CLIENTCERT_FILE=/$DATA/tls/$PEER_NAME-cli-client.crt
   export CORE_PEER_TLS_CLIENTKEY_FILE=/$DATA/tls/$PEER_NAME-cli-client.key
   export CORE_PEER_PROFILE_ENABLED=true
   # gossip variables
   export CORE_PEER_GOSSIP_USELEADERELECTION=true
   export CORE_PEER_GOSSIP_ORGLEADER=false
   export CORE_PEER_GOSSIP_EXTERNALENDPOINT=$PEER_HOST:7051
   if [ $NUM -gt 1 ]; then
      # Point the non-anchor peers to the anchor peer, which is always the 1st peer
      export CORE_PEER_GOSSIP_BOOTSTRAP=peer1-${ORG}:7051
   fi
   export ORDERER_CONN_ARGS="$ORDERER_PORT_ARGS --keyfile $CORE_PEER_TLS_CLIENTKEY_FILE --certfile $CORE_PEER_TLS_CLIENTCERT_FILE"
}

# Switch to the current org's admin identity.  Enroll if not previously enrolled.
function switchToAdminIdentity {
   if [ ! -d $ORG_ADMIN_HOME ]; then
      dowait "$CA_NAME to start" 60 $CA_LOGFILE $CA_CHAINFILE
      log "Enrolling admin '$ADMIN_NAME' with $CA_HOST ..."
      export FABRIC_CA_CLIENT_HOME=$ORG_ADMIN_HOME
      export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
      fabric-ca-client enroll -d -u https://$ADMIN_NAME:$ADMIN_PASS@$CA_HOST:7054
      # If admincerts are required in the MSP, copy the cert there now and to my local MSP also
      if [ $ADMINCERTS ]; then
         mkdir -p $(dirname "${ORG_ADMIN_CERT}")
         cp $ORG_ADMIN_HOME/msp/signcerts/* $ORG_ADMIN_CERT
         mkdir $ORG_ADMIN_HOME/msp/admincerts
         cp $ORG_ADMIN_HOME/msp/signcerts/* $ORG_ADMIN_HOME/msp/admincerts
      fi
   fi
   export CORE_PEER_MSPCONFIGPATH=$ORG_ADMIN_HOME/msp
}

# Switch to the current org's user identity.  Enroll if not previously enrolled.
function switchToUserIdentity {
   export FABRIC_CA_CLIENT_HOME=/etc/hyperledger/fabric/orgs/$ORG/user
   export CORE_PEER_MSPCONFIGPATH=$FABRIC_CA_CLIENT_HOME/msp
   if [ ! -d $FABRIC_CA_CLIENT_HOME ]; then
      dowait "$CA_NAME to start" 60 $CA_LOGFILE $CA_CHAINFILE
      log "Enrolling user for organization $ORG with home directory $FABRIC_CA_CLIENT_HOME ..."
      export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
      fabric-ca-client enroll -d -u https://$USER_NAME:$USER_PASS@$CA_HOST:7054
      # Set up admincerts directory if required
      if [ $ADMINCERTS ]; then
         ACDIR=$CORE_PEER_MSPCONFIGPATH/admincerts
         mkdir -p $ACDIR
         cp $ORG_ADMIN_HOME/msp/signcerts/* $ACDIR
      fi
   fi
}

function genClientTLSCert {
   if [ $# -ne 3 ]; then
      echo "Usage: genClientTLSCert <host name> <cert file> <key file>: $*"
      exit 1
   fi

   HOST_NAME=$1
   CERT_FILE=$2
   KEY_FILE=$3

   # Get a client cert
   fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $HOST_NAME

   mkdir /$DATA/tls || true
   cp /tmp/tls/signcerts/* $CERT_FILE
   cp /tmp/tls/keystore/* $KEY_FILE
   rm -rf /tmp/tls
}

# Copy the org's admin cert into some target MSP directory
# This is only required if ADMINCERTS is enabled.
function copyAdminCert {
   if [ $# -ne 1 ]; then
      fatal "Usage: copyAdminCert <targetMSPDIR>"
   fi
   if $ADMINCERTS; then
      dstDir=$1/admincerts
      mkdir -p $dstDir
      dowait "$ORG administator to enroll" 60 $SETUP_LOGFILE $ORG_ADMIN_CERT
      cp $ORG_ADMIN_CERT $dstDir
   fi
}

# Create the TLS directories of the MSP folder if they don't exist.
# The fabric-ca-client should do this.
function finishMSPSetup {
   if [ $# -ne 1 ]; then
      fatal "Usage: finishMSPSetup <targetMSPDIR>"
   fi
   if [ ! -d $1/tlscacerts ]; then
      mkdir $1/tlscacerts
      cp $1/cacerts/* $1/tlscacerts
      if [ -d $1/intermediatecerts ]; then
         mkdir $1/tlsintermediatecerts
         cp $1/intermediatecerts/* $1/tlsintermediatecerts
      fi
   fi
}

function awaitSetup {
   dowait "the 'setup' container to finish registering identities, creating the genesis block and other artifacts" $SETUP_TIMEOUT $SETUP_LOGFILE /$SETUP_SUCCESS_FILE
}

# Wait for one or more files to exist
# Usage: dowait <what> <timeoutInSecs> <errorLogFile> <file> [<file> ...]
function dowait {
   if [ $# -lt 4 ]; then
      fatal "Usage: dowait: $*"
   fi
   local what=$1
   local secs=$2
   local logFile=$3
   shift 3
   local logit=true
   local starttime=$(date +%s)
   for file in $*; do
      until [ -f $file ]; do
         if [ "$logit" = true ]; then
            log -n "Waiting for $what ..."
            logit=false
         fi
         sleep 1
         if [ "$(($(date +%s)-starttime))" -gt "$secs" ]; then
            echo ""
            fatal "Failed waiting for $what ($file not found); see $logFile"
         fi
         echo -n "."
      done
   done
   echo ""
}

# Wait for a process to begin to listen on a particular host and port
# Usage: waitPort <what> <timeoutInSecs> <errorLogFile> <host> <port>
function waitPort {
   set +e
   local what=$1
   local secs=$2
   local logFile=$3
   local host=$4
   local port=$5
   nc -z $host $port > /dev/null 2>&1
   if [ $? -ne 0 ]; then
      log -n "Waiting for $what ..."
      local starttime=$(date +%s)
      while true; do
         sleep 1
         nc -z $host $port > /dev/null 2>&1
         if [ $? -eq 0 ]; then
            break
         fi
         if [ "$(($(date +%s)-starttime))" -gt "$secs" ]; then
            fatal "Failed waiting for $what; see $logFile"
         fi
         echo -n "."
      done
      echo ""
   fi
   set -e
}


# log a message
function log {
   if [ "$1" = "-n" ]; then
      shift
      echo -n "##### `date '+%Y-%m-%d %H:%M:%S'` $*"
   else
      echo "##### `date '+%Y-%m-%d %H:%M:%S'` $*"
   fi
}

# fatal a message
function fatal {
   log "FATAL: $*"
   exit 1
}
