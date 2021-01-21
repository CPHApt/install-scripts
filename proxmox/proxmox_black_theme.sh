#!/bin/bash

# USAGE:
# sudo bash -c "$(wget -qLO - https://gitlab.jassuncao.work/cpha/install-scripts/-/raw/master/proxmox/proxmox_black_theme.sh)"
#
# CREDITS:
# https://github.com/Weilbyte/PVEDiscordDark

# Download instalation file
wget https://raw.githubusercontent.com/Weilbyte/PVEDiscordDark/master/PVEDiscordDark.py

# Run script
python3 PVEDiscordDark.py
