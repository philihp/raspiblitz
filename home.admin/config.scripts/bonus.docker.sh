#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install docker"
 echo "bonus.docker.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^docker=" /mnt/hdd/raspiblitz.conf; then
  echo "docker=off" >> /mnt/hdd/raspiblitz.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "### INSTALL DOCKER ###"

  # check if docker is installed
  isInstalled=$(docker -v 2>/dev/null | grep -c "Docker version")
  if [ ${isInstalled} -eq 0 ]; then
    echo "error='already installed'"
    exit 1
  fi

  # run easy install script provided by docker
  # its a copy from https://get.docker.com
  sudo chmod +x /home/admin/assets/get-docker.sh
  sudo /home/admin/assets/get-docker.sh

  # add admin user
  sudo usermod -aG docker admin

  # setting value in raspi blitz config
  sudo sed -i "s/^docker=.*/docker=on/g" /mnt/hdd/raspiblitz.conf
  echo "# docker install done"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspiblitz config
  sudo sed -i "s/^docker=.*/docker=off/g" /mnt/hdd/raspiblitz.conf
  echo "*** REMOVING Docker ***"
  sudo rm -rf /var/lib/docker /etc/docker
  echo "# docker remove done"
  exit 0
fi

echo "error='wrong parameter'"
exit 1