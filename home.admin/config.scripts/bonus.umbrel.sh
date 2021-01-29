#!/bin/bash

# TODOS:
# - if password B is changed from RaspBlitz ... also change in umbrel-middleware & manager
# - create dashboard tor servive and link in manager config 
# - do BITCOIN_P2P_HIDDEN_SERVICE_FILE correct

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# umbrel API & dashboard integration"
 echo "# bonus.umbrel.sh on"
 echo "# bonus.umbrel.sh status"
 echo "# bonus.umbrel.sh off"
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

  # make sure that the tor hostnames are readyble for umbrel
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
    sudo systemctl disable umbrel-middleware
    sudo rm /etc/systemd/system/umbrel-middleware.service
  fi

  # uninstall umbrel-middelware
  isInstalled=$(sudo ls /etc/systemd/system/umbrel-manager.service 2>/dev/null | grep -c 'umbrel-manager.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING umbrel-manager ***"
    sudo systemctl disable umbrel-manager
    sudo rm /etc/systemd/system/umbrel-manager.service
  fi

  # delete umbrel user and hoke directory
  sudo userdel -rf umbrel

  echo "# needs reboot to activate new setting"
  exit 0
fi

echo "error='unknown parameter'"
exit 1