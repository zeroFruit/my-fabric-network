# Hyperledger Fabric Network


## How to build network
```
./start.sh
```

`start.sh` is composed of three parts.
1. Clean up old artifacts, logs, running docker container
2. Generate docker-compose script
3. Run docker containers 

## Network Components
* Organizations: 3
* Root-CA in each organization: 1
* Intermediate-CAs in each organization: 1
* Peers in each organization: 2
* Orderers: 2
* Zookeeper: 3
* kafka: 4

