#!/bin/bash

# NOTES:
# how to ssh into a umbrel node for comparing: https://github.com/getumbrel/umbrel-os#-ssh

# TODOS:
# - if password B is changed from RaspBlitz ... also change in umbrel-middleware & manager
# - create dashboard tor servive and link in manager config 
# - do BITCOIN_P2P_HIDDEN_SERVICE_FILE correct
# - change port of dashboard from 8080 .. collusion with LND-REST 
# - change name/password also in USER_FILE if changed outside

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# umbrel API & dashboard integration"
 echo "# bonus.umbrel.sh on"
 echo "# bonus.umbrel.sh on-docker"
 echo "# bonus.umbrel.sh status"
 echo "# bonus.umbrel.sh update [manager|middleware|dashboard] [githubUser] [githubBranch]"
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

# status
if [ "$1" = "status" ]; then

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

# switch on
if [ "$1" = "on" ] || [ "$1" = "1" ]; then

  # check if umbrel user directory exists
  if [ -d "/home/umbrel" ]; then
    echo "error='already installed'"
    exit 1
  fi

  echo
  echo "# *** Prepare Umbrel Install ***"

  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on
  sudo apt-get install -y yarn

  # create umbrel user
  sudo adduser --disabled-password --gecos "" umbrel

  # make sure umbrel is member of lndadmin
  sudo /usr/sbin/usermod --append --groups lndadmin umbrel

  # make sure symlink to central app-data directory exists
  if ! [[ -L "/home/umbrel/.lnd" ]]; then
    sudo rm -rf "/home/umbrel/.lnd"                          # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/umbrel/.lnd"  # and create symlink
  fi

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

  echo
  echo "# *** INSTALL umbrel-middleware ***"

  # download source code and set to tag release
  echo "# *** get the umbrel middleware source code ***"
  sudo rm -rf /home/umbrel/umbrel-middleware 2>/dev/null
  sudo -u umbrel git clone https://github.com/getumbrel/umbrel-middleware.git /home/umbrel/umbrel-middleware
  cd /home/umbrel/umbrel-middleware
  sudo -u umbrel git reset --hard v0.1.7

  # install
  echo "# *** run npm install ***"
  cd /home/umbrel/umbrel-middleware
  sudo -u umbrel npm install
  if ! [ $? -eq 0 ]; then
      echo "error='npm install failed of umbrel-middleware'"
      exit 1
  else
      echo "# OK - install done"
  fi

  # prepare Config file
  # see details: https://github.com/getumbrel/umbrel-middleware#step-2-set-environment-variables
  echo "# *** write umbrel middleware config ***"
  cat > /home/admin/umbrel-middleware.env <<EOF
PORT=3005
DEVICE_HOSTS="http://localhost:3005,http://127.0.0.1:3005"
BITCOIN_HOST=127.0.0.1
RPC_USER=$bitcoinRpcUser
RPC_PASSWORD=$bitcoinRpcPassword
LND_HOST=127.0.0.1
TLS_FILE="/mnt/hdd/lnd/tls.cert"
LND_PORT=10009
LND_NETWORK=mainnet
MACAROON_DIR="/mnt/hdd/app-data/lnd/data/chain/bitcoin/mainnet/"
JWT_PRIVATE_KEY_FILE="/mnt/hdd/app-data/umbrel/jwt.key"
EOF
  sudo mv /home/admin/umbrel-middleware.env /home/umbrel/umbrel-middleware/.env
  sudo chown umbrel:umbrel /home/umbrel/umbrel-middleware/.env
  sudo chmod 700 /home/umbrel/umbrel-middleware/.env

  # install service
  echo "*** Install umbrel systemd ***"
  cat > /home/admin/umbrel-middleware.service <<EOF
# Systemd unit for umbrel-middleware

[Unit]
Description=umbrel-middleware
Wants=lnd.service
After=lnd.service
[Service]
WorkingDirectory=/home/umbrel/umbrel-middleware
EnvironmentFile=/home/umbrel/umbrel-middleware/.env
ExecStart=npm start
User=umbrel
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  sudo mv /home/admin/umbrel-middleware.service /etc/systemd/system/umbrel-middleware.service
  sudo chown root:root /etc/systemd/system/umbrel-middleware.service
  sudo systemctl enable umbrel-middleware.service
  echo "# umbrel-middleware service is now enabled"

  if [ "${setupStep}" == "100" ]; then
    sudo systemctl start umbrel-middleware.service
    echo "OK - the umbrel-middleware service got started"
  else
    echo "OK - will start after reboot"
  fi

  echo 
  echo "# *** INSTALL umbrel-manager ***"

  # download source code and set to tag release
  echo "# *** get the umbrel manager source code ***"
  sudo rm -rf /home/umbrel/umbrel-manager 2>/dev/null
  sudo -u umbrel git clone https://github.com/getumbrel/umbrel-manager.git /home/umbrel/umbrel-manager
  cd /home/umbrel/umbrel-manager
  sudo -u umbrel git reset --hard v0.2.9

  # install
  echo "# *** run npm install ***"
  cd /home/umbrel/umbrel-manager
  sudo -u umbrel npm install
  if ! [ $? -eq 0 ]; then
      echo "error='npm install failed of umbrel-manager'"
      exit 1
  else
      echo "# OK - install done"
  fi

  # prepare needed files for config (if not existing yet)
  if ! [ -f "/mnt/hdd/app-data/umbrel/update-status.json" ]; then
    echo -e '{\n"state": "success",\n"progress": 100,\n"description": "",\n"updateTo": ""\n}' > /home/admin/template.tmp
    sudo mv /home/admin/template.tmp /mnt/hdd/app-data/umbrel/update-status.json
    sudo chown umbrel:umbrel /mnt/hdd/app-data/umbrel/update-status.json
  fi
  if ! [ -f "/mnt/hdd/app-data/umbrel/user.json" ]; then
    echo -e "{\n\"name\": \"$hostname\",\n\"password\": \"$bitcoinRpcPassword\",\n\"seed\": \"\",\n\"installedApps\": []\n}" > /home/admin/template.tmp
    sudo mv /home/admin/template.tmp /mnt/hdd/app-data/umbrel/user.json
    sudo chown umbrel:umbrel /mnt/hdd/app-data/umbrel/user.json
  fi

  # prepare Config file
  # see details: https://github.com/getumbrel/umbrel-manager#step-2-set-environment-variables
  echo "# *** write umbrel manager config ***"
  cat > /home/admin/umbrel-manager.env <<EOF
PORT=3006
DEVICE_HOSTS="http://localhost:3006,http://127.0.0.1:3006"
USER_FILE="/mnt/hdd/app-data/umbrel/user.json"
SHUTDOWN_SIGNAL_FILE="/mnt/hdd/app-data/umbrel/shutdown.signal"
REBOOT_SIGNAL_FILE="/mnt/hdd/app-data/umbrel/reboot.signal"
MIDDLEWARE_API_URL="http://localhost"
MIDDLEWARE_API_PORT=3005
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
TOR_PROXY_IP="127.0.0.1"
TOR_PROXY_PORT=9050
EOF
  sudo mv /home/admin/umbrel-manager.env /home/umbrel/umbrel-manager/.env
  sudo chown umbrel:umbrel /home/umbrel/umbrel-manager/.env
  sudo chmod 700 /home/umbrel/umbrel-manager/.env

  # install service
  echo "*** Install umbrel-manager systemd ***"
  cat > /home/admin/umbrel-manager.service <<EOF
# Systemd unit for umbrel-manager

[Unit]
Description=umbrel-manager
Wants=lnd.service
After=lnd.service
[Service]
WorkingDirectory=/home/umbrel/umbrel-manager
EnvironmentFile=/home/umbrel/umbrel-manager/.env
ExecStart=npm start
User=umbrel
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  sudo mv /home/admin/umbrel-manager.service /etc/systemd/system/umbrel-manager.service
  sudo chown root:root /etc/systemd/system/umbrel-manager.service
  sudo systemctl enable umbrel-manager.service
  echo "# umbrel-manager service is now enabled"

  if [ "${setupStep}" == "100" ]; then
    sudo systemctl start umbrel-manager.service
    echo "OK - the umbrel-manager service got started"
  else
    echo "OK - will start after reboot"
  fi

  # open firewall
  echo "*** Updating Firewall ***"
  sudo ufw allow 3006 comment 'umbrel-test HTTP'
  echo ""

  echo "# *** Umbrel Dashboard -> umbrel-dashboard.service ***"

  # download source code and set to tag release
  echo "# *** get the umbrel dashboard source code ***"
  sudo rm -rf /home/umbrel/umbrel-dashboard 2>/dev/null
  sudo -u umbrel git clone https://github.com/getumbrel/umbrel-dashboard.git /home/umbrel/umbrel-dashboard
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
VUE_APP_MANAGER_API_URL="http://localhost:3006"
VUE_APP_MIDDLEWARE_API_URL="http://localhost:3005"
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

  exit 0
fi

# update (for development)
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

    if [ "${repo}" != "dashboard" ]; then
      echo "# stopping systemd service" 
      sudo systemctl stop umbrel-${repo}
    fi

    echo "# checksum of pre-update package.json "
    preChecksum=$(sudo find /home/umbrel/umbrel-manager/package.json -type f -exec md5sum {} \; | md5sum)
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

    echo "# check if update of dependencies is needed"
    if [ "${preChecksum}" = "${postChecksum}" ]; then
      echo "# --> no new dependencies"
    else
      echo "# --> change detected --> running npm install"
      sudo -u umbrel npm install
    fi

    if [ "${repo}" = "dashboard" ]; then
      echo "# *** run npm build ***"
      cd /home/umbrel/umbrel-dashboard
      sudo -u umbrel npm run-script build
      if ! [ $? -eq 0 ]; then
        echo "error='npm build failed of umbrel-dashboard'"
        exit 1
      fi
      sudo chmod 755 -R /home/umbrel/umbrel-dashboard/dist
      echo "# OK - build done"
    else
      echo "# starting systemd umbrel-${repo}"
      sudo systemctl start umbrel-${repo} 2>/dev/null    
    fi
    
    echo "# done"
    exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^umbrel=.*/umbrel=off/g" /mnt/hdd/raspiblitz.conf

  # uninstall umbrel-middelware
  isInstalled=$(sudo ls /etc/systemd/system/umbrel-middleware.service 2>/dev/null | grep -c 'umbrel-middleware.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING umbrel-middleware ***"
    sudo systemctl stop umbrel-middleware
    sudo systemctl disable umbrel-middleware
    sudo rm /etc/systemd/system/umbrel-middleware.service
    sudo systemctl daemon-reload
  fi

  # uninstall umbrel-middelware
  isInstalled=$(sudo ls /etc/systemd/system/umbrel-manager.service 2>/dev/null | grep -c 'umbrel-manager.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING umbrel-manager ***"
    sudo systemctl stop umbrel-manager
    sudo systemctl disable umbrel-manager
    sudo rm /etc/systemd/system/umbrel-manager.service
    sudo systemctl daemon-reload
  fi

  # delete the docker images
  docker image rm -f $(docker images 'umbrel-middleware' -a -q)
  docker image rm -f $(docker images 'umbrel-manager' -a -q)

  # delete umbrel user and hoke directory
  echo "# *** REMOVING user umbrel ***"
  sudo userdel -rf umbrel

  echo "# needs reboot to activate new setting"
  exit 0
fi

# install and run manager & middleware in docker
if [ "$1" = "on-docker" ]; then
  
  # create umbrel user
  sudo adduser --disabled-password --gecos "" umbrel

  # make sure umbrel is member of lndadmin
  sudo /usr/sbin/usermod --append --groups lndadmin umbrel

  # make sure that docker is installed
  /home/admin/config.scripts/bonus.docker.sh on

  # add umbrel user to docker group
  sudo usermod -aG docker umbrel

  # download source code for middleware and build docker
  echo "# *** get the umbrel middleware source code ***"
  sudo rm -rf /home/umbrel/umbrel-middleware 2>/dev/null
  sudo -u umbrel git clone https://github.com/getumbrel/umbrel-middleware.git /home/umbrel/umbrel-middleware
  cd /home/umbrel/umbrel-middleware
  sudo -u umbrel git reset --hard v0.1.7
  sudo -u umbrel docker build -t umbrel-middleware .
  
  # write enviroment file with config
  # see details: https://github.com/getumbrel/umbrel-middleware#step-2-set-environment-variables
  echo "# *** write umbrel middleware config ***"
  cat > /home/admin/umbrel-middleware.env <<EOF
PORT=3006
DEVICE_HOSTS="http://localhost:3005,http://127.0.0.1:3005"
BITCOIN_HOST=127.0.0.1
RPC_USER=$bitcoinRpcUser
RPC_PASSWORD=$bitcoinRpcPassword
LND_HOST=127.0.0.1
TLS_FILE="/mnt/hdd/lnd/tls.cert"
LND_PORT=10009
LND_NETWORK=mainnet
MACAROON_DIR="/mnt/hdd/app-data/lnd/data/chain/bitcoin/mainnet/"
JWT_PRIVATE_KEY_FILE="/mnt/hdd/app-data/umbrel/jwt.key"
EOF
  sudo mv /home/admin/umbrel-middleware.env /home/umbrel/umbrel-middleware/.env
  sudo chown umbrel:umbrel /home/umbrel/umbrel-middleware/.env
  sudo chmod 700 /home/umbrel/umbrel-middleware/.env

  # install service
  echo "*** Install umbrel systemd ***"
  cat > /home/admin/umbrel-middleware.service <<EOF
# Systemd unit for umbrel-middleware

[Unit]
Description=umbrel-middleware
Wants=lnd.service
After=lnd.service
[Service]
WorkingDirectory=/home/umbrel/umbrel-middleware
EnvironmentFile=/home/umbrel/umbrel-middleware/.env
ExecStart=docker run -p 3005:3005 umbrel-middleware
ExecStop=docker stop umbrel-middleware
User=umbrel
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  sudo mv /home/admin/umbrel-middleware.service /etc/systemd/system/umbrel-middleware.service
  sudo chown root:root /etc/systemd/system/umbrel-middleware.service
  sudo systemctl enable umbrel-middleware.service
  echo "# umbrel-middleware service is now enabled"

  
  echo "TODO: finish implementation"
  exit 0
fi

echo "error='unknown parameter'"
exit 1