#!/bin/bash


#########################################
# NETWORK
#########################################

# Name of the docker-compose network
NETWORK=my-network

# Names of the orderer organizations
ORDERER_ORGS="org0"
# Number of orderer nodes
NUM_ORDERERS=1

# Names of the peer organizations
PEER_ORGS=""
# Number of peer nodes
NUM_PEERS=0

# All org names
ORGS="$ORDERER_ORGS $PEER_ORGS"

# Set to true to populate the "admincerts" folder of MSPs
ADMINCERTS=true

# The volume mount to share data between containers
DATA=data


GENESIS_BLOCK_FILE=/$DATA/genesis.block
CHANNEL_TX_FILE=/$DATA/channel.tx
CHANNEL_NAME=mychannel




#########################################
# Log
#########################################
LOGDIR=$DATA/logs
LOGPATH=/$LOGDIR

# Name of a the file to create when setup is successful
SETUP_SUCCESS_FILE=${LOGDIR}/setup.successful
# The setup container's log file
SETUP_LOGFILE=${LOGDIR}/setup.log



#########################################
# Etc
#########################################
# Setup timeout in seconds (for setup container to complete)
SETUP_TIMEOUT=120



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

    # Root CA admin identity
    ROOT_CA_ADMIN_USER=rca-${ORG}-admin
    ROOT_CA_ADMIN_PASS=${ROOT_CA_ADMIN_USER}pw
    ROOT_CA_ADMIN_USER_PASS=${ROOT_CA_ADMIN_USER}:${ROOT_CA_ADMIN_PASS}

    # Admin identity for the org
    ADMIN_NAME=admin-${ORG}
    ADMIN_PASS=${ADMIN_NAME}pw
    # Typical user identity for the org
    USER_NAME=user-${ORG}
    USER_PASS=${USER_NAME}pw

    ROOT_CA_CERTFILE=/${DATA}/${ORG}-ca-cert.pem

    ORG_MSP_ID=${ORG}MSP
    ORG_MSP_DIR=/${DATA}/orgs/${ORG}/msp

    ORG_ADMIN_CERT=${ORG_MSP_DIR}/admincerts/cert.pem
    ORG_ADMIN_HOME=/${DATA}/orgs/$ORG/admin

    # CA
    CA_NAME=$ROOT_CA_NAME
    CA_HOST=$ROOT_CA_HOST
    CA_CHAINFILE=$ROOT_CA_CERTFILE
    CA_ADMIN_USER_PASS=$ROOT_CA_ADMIN_USER_PASS
    CA_LOGFILE=$ROOT_CA_LOGFILE
}

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
}


################################################################################
#
#   HELPER
#
################################################################################

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


################################################################################
#
#   UTIL
#
################################################################################

# printOrg
function printOrg {
   echo "
  - &$ORG_CONTAINER_NAME

    Name: $ORG

    # ID to load the MSP definition as
    ID: $ORG_MSP_ID

    # MSPDir is the filesystem path which contains the MSP configuration
    MSPDir: $ORG_MSP_DIR"
}

# printOrdererOrg <ORG>
function printOrdererOrg {
   initOrgVars $1
   printOrg
}

# printPeerOrg <ORG> <COUNT>
function printPeerOrg {
   initPeerVars $1 $2
   printOrg
   echo "
    AnchorPeers:
       # AnchorPeers defines the location of peers which can be used
       # for cross org gossip communication.  Note, this value is only
       # encoded in the genesis block in the Application section context
       - Host: $PEER_HOST
         Port: 7051"
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