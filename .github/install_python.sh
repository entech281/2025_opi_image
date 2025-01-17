#!/bin/bash

set -ex

curl -fsSL https://pyenv.run | bash
export PATH="/home/ubuntu/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
cat >> /home/ubuntu/.bashrc EOF#

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
eval "$(pyenv virtualenv-init -)"
EOF

pyenv install 3.11.11
pyenv virtualenv 3.11.11 venv
pyenv activate venv
pip install --upgrade pip
pip install numpy opencv-python
pip install --extra-index-url=https://wpilib.jfrog.io/artifactory/api/pypi/wpilib-python-release-2025/simple robotpy robotpy_cscore robotpy_apriltag
