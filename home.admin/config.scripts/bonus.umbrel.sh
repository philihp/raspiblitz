#!/bin/bash

############
# NOTES:
# how to ssh into a umbrel node for comparing: https://github.com/getumbrel/umbrel-os#-ssh

# TODOS:
# - if password B is changed from RaspBlitz ... also change in middleware, manager & reset user
# - create dashboard tor servive and link in manager config 
# - do BITCOIN_P2P_HIDDEN_SERVICE_FILE correct
# - make sure Tor is on
# - find better way to set DEVICE_HOSTS or update localip on every start

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# umbrel API & dashboard integration"
 echo "# bonus.umbrel.sh on"
 echo "# bonus.umbrel.sh status"
 echo "# bonus.umbrel.sh logs"
 echo "# bonus.umbrel.sh update [manager|middleware|dashboard] [githubUser] [githubBranch]"
 echo "# bonus.umbrel.sh patch [manager|middleware|dashboard]"
 echo "# bonus.umbrel.sh off"
 echo "####################################"
 echo "# To follow logs:"
 echo "# sudo journalctl -u umbrel-manager -f"
 echo "# sudo journalctl -u umbrel-middleware -f"
 exit 1
fi

# check and load raspiblitz config & info file
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

source <(/home/admin/config.scripts/internet.sh status)

### STATUS ###
# region
if [ "$1" = "status" ]; then

  echo "# *** Umbrel Systemd Docker-Compose ***"

  if [ -f "/etc/systemd/system/umbrel.service" ]; then
    echo "umbrelService=on"  

    # check systemd service for docker-compose is running
    serviceRunning=$(sudo systemctl status umbrel 2>/dev/null | grep -c "active (running)")
    echo "umbrelRunning=${serviceRunning}"
    if [ "${serviceRunning}" == "0" ]; then
      echo "# WARNING: systemd service for umbrel not running"
      echo "# check --> sudo systemctl status umbrel"
      echo "# check --> sudo journalctl -u umbrel"
      echo "# try --> sudo systemctl start umbrel"
      exit 1
    fi  

    # check if single containers are "Up"
    cd /home/umbrel
    containerManager=$(sudo -u umbrel docker-compose ps | grep "manager" | grep -c "Up")
    echo "containerManager=${containerManager}"
    containerMiddleware=$(sudo -u umbrel docker-compose ps | grep "middleware" | grep -c "Up")
    echo "containerMiddleware=${containerMiddleware}"
    if [ ${containerManager} -eq 0 ] || [ ${containerMiddleware} -eq 0 ]; then
      echo "# WARNING: systemd serive umbrel is running, but"
      echo "# docker-compose shows that not all needed containers are UP"
      echo "# check --> sudo docker-compose -f /home/umbrel/docker-compose.yml ps"
      echo "# check --> sudo journalctl -u umbrel"
      exit 1
    fi

    # check if http services of containers react to ping
    pingURL="http://127.0.0.1:3006/ping"
    middlewarePing=$(curl ${pingURL} 2>/dev/null | grep -c "umbrel-middleware-")
    echo "middlewarePing=${middlewarePing}"
    if [ "${middlewarePing}" == "0" ]; then
      echo "# WARNING: middleware nodjs not responding to ping"
      echo "# check --> curl ${pingURL}"
      echo "# check --> sudo journalctl -u umbrel-middleware"
    fi
    pingURL="http://127.0.0.1:3005/ping"
    managerPing=$(curl ${pingURL} 2>/dev/null | grep -c "umbrel-manager-")
    echo "managerPing=${managerPing}"
    if [ "${managerPing}" == "0" ]; then
      echo "# WARNING: manager nodjs not responding to ping"
      echo "# check --> curl ${pingURL}"
      echo "# check --> sudo journalctl -u umbrel-manager"
    fi

  else
    echo "umbrelService=off"  
  fi

  echo "# TODO: implement rest of status check"
  exit 0

  echo "# *** Umbrel Middleware -> umbrel-middleware.service ***"

  # check if service is installed
  if [ -f "/etc/systemd/system/umbrel-middleware.service" ]; then
    echo "middlewareService=on"  

    # check if service is running
    middlewareRunning=$(sudo systemctl status umbrel-middleware 2>/dev/null | grep -c "active (running)")
    echo "middlewareRunning=${middlewareRunning}"
    if [ "${middlewareRunning}" == "0" ]; then
      echo "# WARNING: systemd service for middleware not running"
      echo "# check --> sudo systemctl status umbrel-middleware"
    fi    

    # check if local ping is working
    middlewarePing=$(curl http://127.0.0.1:3005/ping 2>/dev/null | grep -c "umbrel-middleware-")
    echo "middlewarePing=${middlewarePing}"
    if [ "${middlewarePing}" == "0" ]; then
      echo "# WARNING: middleware nodjs not responding locally on port 3005"
      echo "# check --> sudo journalctl -u umbrel-middleware"
    fi  

  else
    echo "middlewareService=off"
  fi

  echo "# *** Umbrel Manager -> umbrel-manager.service ***"

 # check if service is installed
  if [ -f "/etc/systemd/system/umbrel-manager.service" ]; then
    echo "managerService=on"  

    # check if service is running
    managerRunning=$(sudo systemctl status umbrel-manager 2>/dev/null | grep -c "active (running)")
    echo "managerRunning=${managerRunning}"
    if [ "${managerRunning}" == "0" ]; then
      echo "# WARNING: systemd service for manager not running"
      echo "# check --> sudo systemctl status umbrel-manager"
    fi    

    # check if local ping is working
    managerPing=$(curl http://127.0.0.1:3006/ping 2>/dev/null | grep -c "umbrel-manager-")
    echo "managerPing=${managerPing}"
    if [ "${managerPing}" == "0" ]; then
      echo "# WARNING: manager nodjs not responding locally on port 3005"
      echo "# check --> sudo journalctl -u umbrel-manager"
    fi  

  else
    echo "managerService=off"  
  fi

  exit 0
fi
# endregion

### LOGS ###
# region
if [ "$1" = "logs" ]; then

  # get docker container ids
  containerManager=$(sudo -u umbrel docker ps | grep "umbrel-manager" | cut -d " " -f1)
  containerMiddleware=$(sudo -u umbrel docker ps | grep "umbrel-middleware" | cut -d " " -f1)

  echo "### HOW TO GET UMBREL LOGS:"
  echo "# manager    --> docker logs -n 100 --follow ${containerManager}" 
  echo "# middleware --> docker logs -n 100 --follow ${containerMiddleware}"
  echo "# dashboard  --> sudo tail -fn 100 /var/log/nginx/access.log"
  echo "#            --> sudo tail -fn 100 /var/log/nginx/error.log"
  exit 0
fi
# endregion

### ON ###
# region
if [ "$1" = "on" ]; then
  
  ################################
  # UMBREL USER & PREPERATIONS
  ################################

  echo "# *** Umbrel User ***"

  # create umbrel user
  sudo adduser --disabled-password --gecos "" umbrel

  # make sure umbrel is member of lndadmin
  sudo /usr/sbin/usermod --append --groups lndadmin umbrel

  # make sure that docker is installed
  /home/admin/config.scripts/bonus.docker.sh on

  # add umbrel user to docker group
  sudo usermod -aG docker umbrel
  sudo usermod -aG bitcoin umbrel

  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # create data directory for umbrel
  sudo mkdir /mnt/hdd/app-data/umbrel 2>/dev/null
  sudo chown -R umbrel:umbrel /mnt/hdd/app-data/umbrel

  # make sure that the tor hostnames are readable for umbrel
  sudo chmod 644 /mnt/hdd/tor/web80/hostname
  sudo chmod 644 /mnt/hdd/tor/electrs/hostname
  sudo chmod 644 /mnt/hdd/tor/bitcoin8332/hostname

  # getting the RPC password (will be used for configs later on)
  bitcoinRpcUser=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep 'rpcuser=' | cut -d '=' -f2)
  bitcoinRpcPassword=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep 'rpcpassword=' | cut -d '=' -f2)

  ################################
  # UMIDDLEWARE
  ################################

  echo "# *** Umbrel Middleware ***"

  # download source code
  echo "# *** get the umbrel middleware source code ***"
  sudo rm -rf /home/umbrel/umbrel-middleware 2>/dev/null
  sudo -u umbrel git clone https://github.com/rootzoll/umbrel-middleware.git /home/umbrel/umbrel-middleware
  cd /home/umbrel/umbrel-middleware
  sudo -u umbrel git reset --hard v0.1.7

  # build docker image and create constainer
  sudo -u umbrel docker build -t umbrel-middleware .

  # write enviroment file with config
  # see details: https://github.com/getumbrel/umbrel-middleware#step-2-set-environment-variables
  echo "# *** write umbrel middleware config ***"
  cat > /home/admin/umbrel-middleware.env <<EOF
PORT=3006
DEVICE_HOSTS="http://localhost:3005,http://127.0.0.1:3005,http://{localip}"
BITCOIN_HOST=10.21.21.1
RPC_USER=$bitcoinRpcUser
RPC_PASSWORD=$bitcoinRpcPassword
LND_HOST=10.21.21.1
TLS_FILE="/mnt/hdd/lnd/tls.cert"
LND_PORT=10009
LND_NETWORK=mainnet
MACAROON_DIR="/mnt/hdd/app-data/lnd/data/chain/bitcoin/mainnet/"
JWT_PUBLIC_KEY_FILE="/mnt/hdd/app-data/umbrel/jwt.pem"
JWT_PRIVATE_KEY_FILE="/mnt/hdd/app-data/umbrel/jwt.key"
EOF
  sudo mv /home/admin/umbrel-middleware.env /home/umbrel/umbrel-middleware/.env
  sudo chown umbrel:umbrel /home/umbrel/umbrel-middleware/.env
  sudo chmod 700 /home/umbrel/umbrel-middleware/.env

  ################################
  # MANAGER
  ################################

  echo "# *** Umbrel Manager ***"

  # download source code and set to tag release
  echo "# get the umbrel manager source code ***"
  sudo rm -rf /home/umbrel/umbrel-manager 2>/dev/null
  sudo -u umbrel git clone https://github.com/rootzoll/umbrel-manager.git /home/umbrel/umbrel-manager
  cd /home/umbrel/umbrel-manager
  sudo -u umbrel git reset --hard v0.2.9

  # build docker image and create constainer
  sudo -u umbrel docker build -t umbrel-manager .

  # prepare needed files for config (if not existing yet)
  if ! [ -f "/mnt/hdd/app-data/umbrel/update-status.json" ]; then
    echo -e '{\n"state": "success",\n"progress": 100,\n"description": "",\n"updateTo": ""\n}' > /home/admin/template.tmp
    sudo mv /home/admin/template.tmp /mnt/hdd/app-data/umbrel/update-status.json
    sudo chown umbrel:umbrel /mnt/hdd/app-data/umbrel/update-status.json
  fi
  #
  #if ! [ -f "/mnt/hdd/app-data/umbrel/user.json" ]; then
  #  echo -e "{\n\"name\": \"$hostname\",\n\"password\": \"$bitcoinRpcPassword\",\n\"seed\": \"\",\n\"installedApps\": []\n}" > /home/admin/template.tmp
  #  sudo mv /home/admin/template.tmp /mnt/hdd/app-data/umbrel/user.json
  #  sudo chown umbrel:umbrel /mnt/hdd/app-data/umbrel/user.json
  #fi

  # prepare Config file
  # see details: https://github.com/getumbrel/umbrel-manager#step-2-set-environment-variables
  echo "# *** write umbrel manager config ***"
  cat > /home/admin/umbrel-manager.env <<EOF
PORT=3005
DEVICE_HOSTS="http://localhost:3006,http://127.0.0.1:3006,http://{localip}"
USER_FILE="/mnt/hdd/app-data/umbrel/user.json"
SHUTDOWN_SIGNAL_FILE="/mnt/hdd/app-data/umbrel/shutdown.signal"
REBOOT_SIGNAL_FILE="/mnt/hdd/app-data/umbrel/reboot.signal"
MIDDLEWARE_API_URL="http://localhost"
MIDDLEWARE_API_PORT=3006
JWT_PUBLIC_KEY_FILE="/mnt/hdd/app-data/umbrel/jwt.pem"
JWT_PRIVATE_KEY_FILE="/mnt/hdd/app-data/umbrel/jwt.key"
JWT_EXPIRATION=3600
DOCKER_COMPOSE_DIRECTORY="/mnt/hdd/app-data/umbrel"
UMBREL_SEED_FILE="/mnt/hdd/app-data/umbrel/seed.file"
UMBREL_DASHBOARD_HIDDEN_SERVICE_FILE="/mnt/hdd/tor/web80/hostname"
ELECTRUM_HIDDEN_SERVICE_FILE="/mnt/hdd/tor/electrs/hostname"
ELECTRUM_PORT=50001
BITCOIN_P2P_HIDDEN_SERVICE_FILE="/mnt/hdd/tor/bitcoin8332/hostname"
BITCOIN_P2P_PORT=8333
BITCOIN_RPC_HIDDEN_SERVICE_FILE="/mnt/hdd/tor/bitcoin8332/hostname"
BITCOIN_RPC_PORT=8332
RPC_USER=$bitcoinRpcUser
RPC_PASSWORD=$bitcoinRpcPassword
GITHUB_REPO="getumbrel/umbrel"
UMBREL_VERSION_FILE="/mnt/hdd/app-data/umbrel/info.json"
UPDATE_STATUS_FILE="/mnt/hdd/app-data/umbrel/update-status.json"
UPDATE_SIGNAL_FILE="/mnt/hdd/app-data/umbrel/update.signal"
UPDATE_LOCK_FILE="/mnt/hdd/app-data/umbrel/update-in-progress.lock"
BACKUP_STATUS_FILE="/mnt/hdd/app-data/umbrel/backup-status.json"
TOR_PROXY_IP="10.21.21.1"
TOR_PROXY_PORT=9050
EOF
  sudo mv /home/admin/umbrel-manager.env /home/umbrel/umbrel-manager/.env
  sudo chown umbrel:umbrel /home/umbrel/umbrel-manager/.env
  sudo chmod 700 /home/umbrel/umbrel-manager/.env

  # start manager once to init user
  echo "# creating user ..."
  sudo -u umbrel docker run --name manager -d umbrel-manager
  sleep 6
  sudo -u umbrel docker cp /home/admin/assets/raspiblitz.js manager:/app
  docker exec -it manager node /app/raspiblitz.js init-user ${hostname} ${bitcoinRpcPassword}
  docker commit manager
  docker rm -f manager

  ################################
  # DOCKER COMPOSE
  ################################

  echo "# *** write umbrel docker-compose for raspiblitz ***"

  cat > /home/admin/docker-compose.yml <<EOF
version: '3.7'
x-logging: &default-logging
    driver: journald
    options:
        tag: "{{.Name}}"

services:
        manager:
                container_name: manager
                image: umbrel-manager
                logging: *default-logging
                restart: on-failure
                stop_grace_period: 5m30s
                volumes:
                        - /mnt/hdd/app-data/umbrel:/mnt/hdd/app-data/umbrel
                        - /mnt/hdd/tor:/mnt/hdd/tor
                env_file:
                        - /home/umbrel/umbrel-manager/.env
                ports:
                        - "3005:3005"
                networks:
                    default:
                        ipv4_address: 10.21.21.4
        middleware:
                container_name: middleware
                image: umbrel-middleware
                logging: *default-logging
                depends_on: [ manager ]
                command: ["npm", "start"]
                restart: on-failure
                volumes:
                        - /mnt/hdd/lnd:/mnt/hdd/lnd
                        - /mnt/hdd/app-data/umbrel:/mnt/hdd/app-data/umbrel
                        - /mnt/hdd/app-data/lnd:/mnt/hdd/app-data/lnd
                env_file:
                        - /home/umbrel/umbrel-middleware/.env
                ports:
                        - "3006:3006"
                networks:
                    default:
                        ipv4_address: 10.21.21.5
networks:
    default:
        name: umbrel_main_network
        ipam:
            driver: default
            config:
                - subnet: "10.21.21.0/24"
EOF
  sudo mv /home/admin/docker-compose.yml /home/umbrel/docker-compose.yml
  sudo chown umbrel:umbrel /home/umbrel/docker-compose.yml
  sudo chmod 700 /home/umbrel/docker-compose.yml

  # install service
  echo "*** Install umbrel systemd ***"
  cat > /home/admin/umbrel.service <<EOF
# Systemd unit for umbrel

[Unit]
Description=umbrel
Requires=docker.service
After=lnd.service
[Service]
WorkingDirectory=/home/umbrel
ExecStart=docker-compose up
ExecStop=docker-compose down
User=umbrel
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  sudo mv /home/admin/umbrel.service /etc/systemd/system/umbrel.service
  sudo chown root:root /etc/systemd/system/umbrel.service
  sudo systemctl enable umbrel.service
  echo "# umbrel service is now enabled"

  ################################
  # DASHBOARD (hosted thru nginx)
  ################################

  echo "# *** Umbrel Dashboard -> umbrel-dashboard.service ***"

  # download source code and set to tag release
  echo "# *** get the umbrel dashboard source code ***"
  sudo rm -rf /home/umbrel/umbrel-dashboard 2>/dev/null
  sudo -u umbrel git clone https://github.com/rootzoll/umbrel-dashboard.git /home/umbrel/umbrel-dashboard
  cd /home/umbrel/umbrel-dashboard
  sudo -u umbrel git reset --hard v0.3.15

  # install
  echo "# *** run npm install ***"
  cd /home/umbrel/umbrel-dashboard
  sudo -u umbrel npm install
  if ! [ $? -eq 0 ]; then
      echo "error='npm install failed of umbrel-dashboard'"
      exit 1
  else
      echo "# OK - install done"
  fi

  # prepare Config file
  # see details: https://github.com/getumbrel/umbrel-dashboard#step-2-set-environment-variables
  echo "# *** write umbrel dashboard config ***"
  cat > /home/admin/umbrel-dashboard.env <<EOF
VUE_APP_MANAGER_API_URL="http://localhost:3005"
VUE_APP_MIDDLEWARE_API_URL="http://localhost:3006"
EOF
  sudo mv /home/admin/umbrel-dashboard.env /home/umbrel/umbrel-dashboard/.env
  sudo chown umbrel:umbrel /home/umbrel/umbrel-dashboard/.env
  sudo chmod 700 /home/umbrel/umbrel-dashboard/.env

  # npm build
  echo "# *** run npm build ***"
  cd /home/umbrel/umbrel-dashboard
  sudo -u umbrel npm run-script build
  if ! [ $? -eq 0 ]; then
      echo "error='npm build failed of umbrel-dashboard'"
      exit 1
  fi
  echo "# OK - build done"

  # make sure the dashbaord can be served by nginx
  sudo chmod 755 -R /home/umbrel/umbrel-dashboard/dist

  ################################
  # FINAL SETTINGS
  ################################

  echo "# *** Final Settings for Umbrel ***"

  # open firewall for docker services (testing umbrel)
  sudo ufw allow 3005 comment 'umbrel-test HTTP'
  sudo ufw allow 3006 comment 'umbrel-test HTTP'
  sudo ufw allow from 10.21.21.0/24 comment 'umbrel-docker-network'

  echo "# configuring bitcoind ..."
  alreadyDone=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep -c "# serve RPC on docker")
  if [ ${alreadyDone} -eq 0 ]; then
    sudo systemctl stop bitcoind 2>/dev/null
    echo "" | sudo tee -a /mnt/hdd/bitcoin/bitcoin.conf
    echo "# serve RPC on docker network & allow umbrel-middleware" | sudo tee -a /mnt/hdd/bitcoin/bitcoin.conf
    echo "rpcallowip=10.21.21.0/24" | sudo tee -a /mnt/hdd/bitcoin/bitcoin.conf
    echo "main.rpcbind=10.21.21.1:8332" | sudo tee -a /mnt/hdd/bitcoin/bitcoin.conf
  else
    echo "# ... ok already configured"
  fi

  echo "# configuring lnd ..."
  alreadyDone=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c "rpclisten=10.21.21.1:10009")
  if [ ${alreadyDone} -eq 0 ]; then
    sudo systemctl stop lnd 2>/dev/null
    sudo sed -i "13itlsextraip=10.21.21.1:10009" /mnt/hdd/lnd/lnd.conf
    /home/admin/config.scripts/lnd.tlscert.sh ip-add 10.21.21.5
    /home/admin/config.scripts/lnd.tlscert.sh refresh
  else
    echo "# ... ok already configured"
  fi

  echo "# OK - reboot is needed"
  exit 0
fi
# endregion

### UPDATE (for development) ###
# region
if [ "$1" = "update" ]; then

    # get parameter
    repo=$2
    user=$3
    branch=$4

    # check & set default parameter values
    if [ "${branch}" = "" ]; then
      branch="master"
    fi
    if [ "${user}" = "" ]; then
      user="rootzoll"
    fi
    if [ "${repo}" != "middleware" ] && [ "${repo}" != "manager" ] && [ "${repo}" != "dashboard" ]; then
      echo "error='wrong parameter'"
      exit 1
    fi

    echo "# checksum of pre-update package.json "
    preChecksum=$(sudo find /home/umbrel/umbrel-${repo}/package.json -type f -exec md5sum {} \; | md5sum)
    echo "# --> ${preChecksum}"

    echo "# updating from: github.com/${user}/umbrel-${repo} branch(${branch})"
    cd /home/umbrel/umbrel-${repo}
    sudo -u umbrel git remote set-url origin https://github.com/${user}/umbrel-${repo}.git

    echo "# checking if branch is locally available"
    localBranch=$(sudo -u umbrel git branch | grep -c "${branch}")
    if [ ${localBranch} -eq 0 ]; then
      echo "# checking branch exists .."
      branchExists=$(curl -s https://api.github.com/repos/${user}/umbrel-${repo}/branches/${branch} | jq -r '.name' | grep -c ${branch})
      if [ ${branchExists} -eq 0 ]; then
        echo "error='branch not found'"
        exit 1
      fi
      echo "# checkout branch .."
      sudo -u umbrel git fetch
      sudo -u umbrel git checkout -b ${branch} origin/${branch}
    else
      echo "# setting branch .."
      sudo -u umbrel git checkout ${branch}
    fi
    sudo -u umbrel git pull 1>&2

    echo "# checksum of post-update package.json "
    postChecksum=$(sudo find /home/umbrel/umbrel-manager/package.json -type f -exec md5sum {} \; | md5sum)
    echo "# --> ${postChecksum}"

    # update dashboard
    if [ "${repo}" = "dashboard" ]; then

      echo "### UPDATE DASHBOARD MANAGER ### "
      cd /home/umbrel/umbrel-dashboard

      echo "# check if update of dependencies is needed"
      if [ "${preChecksum}" = "${postChecksum}" ]; then
        echo "# --> no new dependencies"
      else
        echo "# --> change detected --> running npm install"
        sudo -u umbrel npm install
      fi

      echo "# *** run npm build ***"
      sudo -u umbrel npm run-script build
      if ! [ $? -eq 0 ]; then
        echo "error='npm build failed of umbrel-dashboard'"
        exit 1
      fi
      sudo chmod 755 -R /home/umbrel/umbrel-dashboard/dist
      echo "# OK - build done"
      exit 0

    fi

    echo "# stopping systemd service (docker-compose)" 
    sudo systemctl stop umbrel

    # update middleware
    if [ "${repo}" = "middleware" ]; then

      echo "# deleting old docker image of middleware"
      sudo -u umbrel docker image rm -f $(sudo -u umbrel docker images 'umbrel-middleware' -a -q) 2>/dev/null

      echo "# building new docker image of middleware with updated code"
      cd /home/umbrel/umbrel-middleware
      sudo -u umbrel docker build -t umbrel-middleware .
    fi

    # update manager
    if [ "${repo}" = "manager" ]; then

      echo "# deleting old docker image of manager"
      sudo -u umbrel docker image rm -f $(sudo -u umbrel docker images 'umbrel-manager' -a -q) 2>/dev/null

      echo "# building new docker image of manager with updated code"
      cd /home/umbrel/umbrel-manager
      sudo -u umbrel docker build -t umbrel-manager .
    fi

    echo "# starting systemd service (docker-compose)" 
    sudo systemctl start umbrel

    echo "# OK your container should now run the latest code from ${user}/${repo} branch ${branch}" 
    echo "# call for logs info --> /home/admin/config.scripts/bonus.umbrel.sh logs" 
    exit 0
fi
# endregion

### PATCH (for development) ###
# region
if [ "$1" = "patch" ]; then

  # get & check parameter
  repo=$2
  if [ "${repo}" != "middleware" ] && [ "${repo}" != "manager" ] && [ "${repo}" != "dashboard" ]; then
    echo "error='wrong parameter'"
    exit 1
  fi

  cd /home/umbrel/umbrel-${repo}
  echo "# checksum of pre-update package.json "
  preChecksum=$(sudo find /home/umbrel/umbrel-${repo}/package.json -type f -exec md5sum {} \; | md5sum)
  echo "# --> ${preChecksum}"

  sudo -u umbrel git fetch
  sudo -u umbrel git pull

  echo "# checksum of post-update package.json "
  postChecksum=$(sudo find /home/umbrel/umbrel-${repo}/package.json -type f -exec md5sum {} \; | md5sum)
  echo "# --> ${postChecksum}"

  # update dashboard
  if [ "${repo}" = "dashboard" ]; then

    echo "### UPDATE DASHBOARD MANAGER ### "
    cd /home/umbrel/umbrel-dashboard

    echo "# check if update of dependencies is needed"
    if [ "${preChecksum}" = "${postChecksum}" ]; then
      echo "# --> no new dependencies"
    else
      echo "# --> change detected --> running npm install"
      sudo -u umbrel npm install
    fi

    echo "# *** run npm build ***"
    sudo -u umbrel npm run-script build
    if ! [ $? -eq 0 ]; then
      echo "error='npm build failed of umbrel-dashboard'"
      exit 1
    fi
    sudo chmod 755 -R /home/umbrel/umbrel-dashboard/dist
    echo "# OK - build done"
    exit 0
  fi

  # update manager or middleware
  echo "# *** copy new app files into container ***"
  cd /home/umbrel/umbrel-${repo}
  sudo -u umbrel docker cp . ${repo}:/app
  docker exec -it manager yarn install --production
  if [ "${repo}" = "manager" ]; then
    sudo -u umbrel docker cp /home/admin/assets/raspiblitz.js manager:/app
  fi
  
  echo "# *** docker comitting changes to image & restart container ***"
  docker commit ${repo}
  docker restart ${repo}

  echo "# OK your container should now run the latest code" 
  echo "# call for logs info --> /home/admin/config.scripts/bonus.umbrel.sh logs" 
  exit 0
fi
# endregion


### OFF ###
# region
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^umbrel=.*/umbrel=off/g" /mnt/hdd/raspiblitz.conf

  # remove bitcoin.conf entries
  sudo sed -i "s/^# serve RPC on docker.*//g" /mnt/hdd/bitcoin/bitcoin.conf
  sudo sed -i "s/^rpcallowip=10.*//g" /mnt/hdd/bitcoin/bitcoin.conf
  sudo sed -i "s/^main.rpcbind=10.*//g" /mnt/hdd/bitcoin/bitcoin.conf

  # remove lnd.conf entries
  sudo sed -i "/tlsextraip=10.21.21.1:10009/d" /mnt/hdd/lnd/lnd.conf
  /home/admin/config.scripts/lnd.tlscert.sh ip-remove 10.21.21.5

  # uninstall umbrel-middelware
  isInstalled=$(sudo ls /etc/systemd/system/umbrel-middleware.service 2>/dev/null | grep -c 'umbrel-middleware.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING umbrel service ***"
    sudo systemctl stop umbrel
    sudo systemctl disable umbrel
    sudo rm /etc/systemd/system/umbrel.service
    sudo systemctl daemon-reload
  fi

  # delete the docker images
  cd /home/umbrel
  sudo -u umbrel docker-compose rm -f
  sudo -u umbrel docker image rm -f $(sudo -u umbrel docker images 'umbrel-middleware' -a -q) 2>/dev/null
  sudo -u umbrel docker image rm -f $(sudo -u umbrel docker images 'umbrel-manager' -a -q) 2>/dev/null

  # delete umbrel user and hoke directory
  echo "# *** REMOVING user umbrel ***"
  sudo userdel -rf umbrel

  echo "# needs reboot to activate new setting"
  exit 0
fi
# endregion

echo "error='unknown parameter'"
exit 1