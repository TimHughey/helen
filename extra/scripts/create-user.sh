#!/usr/bin/env zsh

pushd -q ${HOME}/devel/helen/extra/zsh

sudo groupadd -g 5001 -f helen
sudo useradd -u 5001 -g 5001 -d /home/helen -s /bin/zsh -c "Helen" -m helen

sudo usermod -G helen thughey

sudo rsync --chown helen:helen -av .zshrc .zshenv /home/helen
