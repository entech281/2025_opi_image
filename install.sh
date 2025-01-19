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



cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  ethernets:
    end1:
      dhcp4: false
      dhcp4-overrides:
        use-dns: false  # Optional: Prevent DHCP from overriding static DNS
      addresses:
        - 10.2.81.11/24  # Static IP address
      routes:
        - to: 0.0.0.0/0
          via: 10.2.81.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
      optional: true  # Ensure the interface doesn't block boot if not ready
EOF


# networkd isn't being used, this causes an unnecessary delay
systemctl disable systemd-networkd-wait-online.service
btservices=$(systemctl list-unit-files *bluetooth.service | tail -n +2 | head -n -1 | awk '{print $1}')
for btservice in $btservices; do
    echo "Masking: $btservice"
    systemctl mask "$btservice"
done


# clean up stuff

# get rid of snaps
rm -rf /var/lib/snapd/seed/snaps/*
rm -f /var/lib/snapd/seed/seed.yaml
apt-get purge --yes --quiet lxd-installer lxd-agent-loader
apt-get purge --yes --quiet bluez
apt-get --yes --quiet autoremove
rm -rf /var/lib/apt/lists/*
apt-get --yes --quiet clean
rm -rf /usr/share/doc
rm -rf /usr/share/locale/



cat > /lib/systemd/system/vision.service <<EOF
[Unit]
Description=Service that runs vision

[Service]
WorkingDirectory=/home/pi/
# Run at "nice" -10, which is higher priority than standard
Nice=-10
# for non-uniform CPUs, like big.LITTLE, you want to select the big cores
# look up the right values for your CPU
# AllowedCPUs=4-7

ExecStart=/home/pi/.pyenv/versions/venv/bin/python /home/pi/vision.py
ExecStop=/bin/systemctl kill $vision
Type=simple
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF



if grep -q "RK3588" /proc/cpuinfo; then
  debug "This has a Rockchip RK3588, enabling big cores"
  sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=4-7/g' /lib/systemd/system/vision.service
fi

cp /lib/systemd/system/vision.service /etc/systemd/system/vision.service
chmod 644 /etc/systemd/system/vision.service
systemctl daemon-reload
systemctl enable vision.service

debug "Created $APP_NAME systemd service."

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/60-limit-log-size.conf << EOF
# Added to keep the logs to a reasonable size
[Journal]
SystemMaxUse=100M
EOF

#set up python, pyenv, and a virtual environment for the pi user
pwd
ls -l 

curl -fsSL https://pyenv.run | bash
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

pyenv install 3.11.11
pyenv virtualenv 3.11.11 venv
pyenv activate venv
pip install --upgrade pip
pip install numpy opencv-python
pip install --extra-index-url=https://wpilib.jfrog.io/artifactory/api/pypi/wpilib-python-release-2025/simple robotpy robotpy_cscore robotpy_apriltag

cp -r -a --dereference /home/runner/.pyenv /home/pi/
cp vision.py /home/pi
chown -R pi:pi /home/pi

echo "127.0.0.1 ubuntu" >> /etc/hosts
