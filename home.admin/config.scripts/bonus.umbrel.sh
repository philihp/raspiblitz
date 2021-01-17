#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# umbrel API & dashboard integration"
 echo "# bonus.umbrel.sh install middleware"
 echo "# bonus.umbrel.sh off"
 exit 1
fi

# check and load raspiblitz config & info file
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# switch on
if [ "$1" = "install" ] && [ "$2" = "middleware" ]; then

  echo "*** INSTALL umbrel-middleware ***"

  isInstalled=$(sudo ls /etc/systemd/system/umbrel-middleware.service 2>/dev/null | grep -c 'umbrel-middleware.service')
  if ! [ ${isInstalled} -eq 0 ]; then
    echo "error='already installed'"
    exit 1
  fi

  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on
  sudo apt-get install -y yarn

  # create rtl user
  sudo adduser --disabled-password --gecos "" umbrel

  echo "# *** make sure umbrel is member of lndadmin ***"
  sudo /usr/sbin/usermod --append --groups lndadmin umbrel

  echo "# *** make sure symlink to central app-data directory exists ***"
  if ! [[ -L "/home/umbrel/.lnd" ]]; then
    sudo rm -rf "/home/umbrel/.lnd"                          # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/umbrel/.lnd"  # and create symlink
  fi

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
      echo "error='npm install falied'"
      exit 1
  else
      echo "# OK - install done"
  fi

  # getting the RPC password
  bitcoinRpcUser=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep 'rpcuser=' | cut -d '=' -f2)
  bitcoinRpcPassword=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep 'rpcpassword=' | cut -d '=' -f2)

  # prepare RTL-Config.json file
  echo "# *** write umbrel middleware config ***"

  # change of config: https://github.com/getumbrel/umbrel-middleware#step-2-set-environment-variables
  cat > /home/admin/umbrel-middleware.env <<EOF
PORT=3005
BITCOIN_HOST=127.0.0.1
RPC_USER=$bitcoinRpcUser
RPC_PASSWORD=$bitcoinRpcPassword
LND_HOST=127.0.0.1
LND_PORT=10009
EOF
  sudo mv /home/admin/umbrel-middleware.env /home/umbrel/umbrel-middleware.env
  sudo chown umbrel:umbrel /home/umbrel/umbrel-middleware.env
  sudo chmod 700 /home/umbrel/umbrel-middleware.env

  # open firewall
  echo "*** Updating Firewall ***"
  sudo ufw allow 3005 comment 'umbrel-middleware HTTP'
  sudo ufw allow 3006 comment 'umbrel-middleware HTTPS'
  echo ""

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
EnvironmentFile=/home/umbrel/umbrel-middleware.env
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

  # delete umbrel user and hoke directory
  sudo userdel -rf umbrel

  # close ports on firewall
  sudo ufw deny 3005
  sudo ufw deny 3006

  echo "# needs reboot to activate new setting"
  exit 0
fi

echo "error='unknown parameter'"
exit 1