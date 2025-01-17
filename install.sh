#!/bin/bash

# This script is drawn from the photon vision scripts
# but removing:
#   any hardware other than orage pi 5
#   anything specific to photonvision
#   anything we dont want, like networkmanager
#   anything that's really for flexible use, like asking users for inputs
#   anything deploying/updating code (we'll do that another way)

# https://github.com/PhotonVision/photon-image-modifier/blob/main/install.sh
# https://github.com/PhotonVision/photon-image-modifier/blob/main/install_common.sh
# https://github.com/PhotonVision/photon-image-modifier/blob/main/install_opi5.sh

# in addition to these, we need to make a python virtual environment, which also requires a lot
# of steps

#MUST RUN AS ROOT
set -ex
QUIET="YES"
debug() {
  if [ -z "$QUIET" ] ; then
    for arg in "$@"; do
      echo "$arg"
    done
  fi
}

apt-get update

#stuff from photonvision, not sure if we need it all
apt-get install -y curl avahi-daemon cpufrequtils v4l-utils libatomic1

#stuff to install python 3.11.11
apt-get install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev
apt-get install -y libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev zlib1g-dev
apt-get install -y ffmpeg libsm6 libxext6 dos2unix


debug "Setting cpufrequtils to performance mode"
if [ -f /etc/default/cpufrequtils ]; then
    sed -i -e 's/^#\?GOVERNOR=.*$/GOVERNOR=performance/' /etc/default/cpufrequtils
else
    echo 'GOVERNOR=performance' > /etc/default/cpufrequtils
fi


# Create pi/raspberry login
if id "pi" >/dev/null 2>&1; then
    echo 'user found'
else
    echo "creating pi user"
    useradd pi -m -b /home -s /bin/bash
    usermod -a -G sudo pi
    echo 'pi ALL=(ALL) NOPASSWD: ALL' | tee -a /etc/sudoers.d/010_pi-nopasswd >/dev/null
    chmod 0440 /etc/sudoers.d/010_pi-nopasswd
fi
echo "pi:raspberry" | chpasswd



# networkd isn't being used, this causes an unnecessary delay
systemctl disable systemd-networkd-wait-online.service
btservices=$(systemctl list-unit-files *bluetooth.service | tail -n +2 | head -n -1 | awk '{print $1}')
for btservice in $btservices; do
    echo "Masking: $btservice"
    systemctl mask "$btservice"
done


# clean up stuff

# get rid of snaps
#rm -rf /var/lib/snapd/seed/snaps/*
#rm -f /var/lib/snapd/seed/seed.yaml
#apt-get purge --yes --quiet lxd-installer lxd-agent-loader
#apt-get purge --yes --quiet bluez
#apt-get --yes --quiet autoremove
#rm -rf /var/lib/apt/lists/*
#apt-get --yes --quiet clean
#rm -rf /usr/share/doc
#rm -rf /usr/share/locale/


#set up python
pwd
ls -l 

curl -fsSL https://pyenv.run | bash
export PATH="/root/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"


pyenv install 3.11.11
pyenv virtualenv 3.11.11 venv
pyenv activate venv
pip install --upgrade pip
pip install numpy opencv-python
pip install --extra-index-url=https://wpilib.jfrog.io/artifactory/api/pypi/wpilib-python-release-2025/simple robotpy robotpy_cscore robotpy_apriltag
cp -R /root/.pyenv /home/py
chown -R pi:pi /home/pi/.pyenv


debug "Set up Network Service"
#mkdir -p /opt/$APP_NAME
cat > /lib/systemd/system/281vision.service <<EOF
[Unit]
Description=Service that runs 281vision

[Service]
WorkingDirectory=/home/pi/
# Run at "nice" -10, which is higher priority than standard
Nice=-10
# for non-uniform CPUs, like big.LITTLE, you want to select the big cores
# look up the right values for your CPU
# AllowedCPUs=4-7

ExecStart=/home/pi/.pyenv/versions/venv/bin/python april2.py
ExecStop=/bin/systemctl kill $281vision
Type=simple
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

# let netplan create the config during cloud-init
#rm -f /etc/netplan/00-default-nm-renderer.yaml

# set NetworkManager as the renderer in cloud-init
#cp -f ./OPi5_CIDATA/network-config /boot/network-config


if grep -q "RK3588" /proc/cpuinfo; then
  debug "This has a Rockchip RK3588, enabling big cores"
  sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=4-7/g' /lib/systemd/system/281vision.service
fi

cp /lib/systemd/system/281vision.service /etc/systemd/system/281vision.service
chmod 644 /etc/systemd/system/281vision.service
systemctl daemon-reload
systemctl enable 281vision.service

debug "Created $APP_NAME systemd service."

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/60-limit-log-size.conf <<EOF
# Added by Photonvision to keep the logs to a reasonable size
[Journal]
SystemMaxUse=100M
EOF

