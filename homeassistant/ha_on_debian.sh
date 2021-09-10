#!/bin/bash

# USAGE:
# sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/CPHApt/install-scripts/master/homeassistant/ha_on_debian.sh)"
#
# Se der um erro, dar o comando `export PATH=$PATH:/usr/sbin` antes de correr o script novamente

# Configure path
export PATH=$PATH:/usr/sbin

# Update, upgrade and clean
apt update && apt upgrade -y && apt autoremove -y

# Install essentials to install HA
apt-get install -y software-properties-common apparmor-utils apt-transport-https avahi-daemon ca-certificates curl dbus jq network-manager

# Disable ModemManager
systemctl disable ModemManager

# Stop ModemManager
systemctl stop ModemManager

# Install Docker
curl -fsSL get.docker.com | sh

# Install HA
set -e

declare -a MISSING_PACAKGES

function info { echo -e "[Info] $*"; }
function error { echo -e "[Error] $*"; exit 1; }
function warn  { echo -e "[Warning] $*"; }

info ""
info ""
info ""
info "Este script foi criado a partir do script oficial"
info ""
info "de instalação do Home Assistant Supervised em"
info ""
info "https://github.com/home-assistant/supervised-installer"
info ""
info ""
info ""

sleep 10

ARCH=$(uname -m)

IP_ADDRESS=$(hostname -I | awk '{ print $1 }')

BINARY_DOCKER=/usr/bin/docker

DOCKER_REPO=homeassistant

SERVICE_DOCKER="docker.service"
SERVICE_NM="NetworkManager.service"

FILE_DOCKER_CONF="/etc/docker/daemon.json"
FILE_NM_CONF="/etc/NetworkManager/NetworkManager.conf"
FILE_NM_CONNECTION="/etc/NetworkManager/system-connections/default"

URL_RAW_BASE="https://raw.githubusercontent.com/home-assistant/supervised-installer/master/files"
URL_VERSION="https://version.home-assistant.io/stable.json"
URL_DOCKER_DAEMON="${URL_RAW_BASE}/docker_daemon.json"
URL_NM_CONF="${URL_RAW_BASE}/NetworkManager.conf"
URL_NM_CONNECTION="${URL_RAW_BASE}/system-connection-default"
URL_HA="${URL_RAW_BASE}/ha"
URL_BIN_HASSIO="${URL_RAW_BASE}/hassio-supervisor"
URL_BIN_APPARMOR="${URL_RAW_BASE}/hassio-apparmor"
URL_SERVICE_HASSIO="${URL_RAW_BASE}/hassio-supervisor.service"
URL_SERVICE_APPARMOR="${URL_RAW_BASE}/hassio-apparmor.service"
URL_APPARMOR_PROFILE="https://version.home-assistant.io/apparmor.txt"

# Check env
command -v systemctl > /dev/null 2>&1 || MISSING_PACAKGES+=("systemd")
command -v nmcli > /dev/null 2>&1 || MISSING_PACAKGES+=("NetworkManager")
command -v apparmor_parser > /dev/null 2>&1 || MISSING_PACAKGES+=("AppArmor")
command -v docker > /dev/null 2>&1 || MISSING_PACAKGES+=("docker")
command -v jq > /dev/null 2>&1 || MISSING_PACAKGES+=("jq")
command -v curl > /dev/null 2>&1 || MISSING_PACAKGES+=("curl")
command -v avahi-daemon > /dev/null 2>&1 || MISSING_PACAKGES+=("avahi")
command -v dbus-daemon > /dev/null 2>&1 || MISSING_PACAKGES+=("dbus")


if [ ! -z "${MISSING_PACAKGES}" ]; then
    warn "Os seguintes pacotes estão em falta e precisam de ser "
    warn "instalados e configurados antes de correres de novo este script"
    error "em falta: ${MISSING_PACAKGES[@]}"
fi

# Check if Modem Manager is enabled
if systemctl list-unit-files ModemManager.service | grep enabled > /dev/null 2>&1; then
    warn "O serviço ModemManager está activo e poderá causar problemas ao usar dispositivos série."
fi

# Detect wrong docker logger config
if [ ! -f "$FILE_DOCKER_CONF" ]; then
  # Write default configuration
  info "A criar a configuração padrão do Docker deamon $FILE_DOCKER_CONF"
  curl -sL ${URL_DOCKER_DAEMON} > "${FILE_DOCKER_CONF}"

  # Restart Docker service
  info "A reiniciar o serviço do Docker"
  systemctl restart "$SERVICE_DOCKER"
else
  STORAGE_DRIVER=$(docker info -f "{{json .}}" | jq -r -e .Driver)
  LOGGING_DRIVER=$(docker info -f "{{json .}}" | jq -r -e .LoggingDriver)
  if [[ "$STORAGE_DRIVER" != "overlay2" ]]; then 
    warn "O Docker está a usar $STORAGE_DRIVER e não 'overlay2' como driver de storage, isto não é suportado."
  fi
  if [[ "$LOGGING_DRIVER"  != "journald" ]]; then 
    warn "O Docker está a usar $LOGGING_DRIVER e não 'journald' como driver de logging, isto não é suportado."
  fi
fi

# Check dmesg access
if [[ "$(sysctl --values kernel.dmesg_restrict)" != "0" ]]; then
    info "A corrigir a restrição do dmesg no kernel"
    echo 0 > /proc/sys/kernel/dmesg_restrict
    echo "kernel.dmesg_restrict=0" >> /etc/sysctl.conf
fi

# Create config for NetworkManager
info "A criar a configuração do NetworkManager"
rm -f /etc/network/interfaces
curl -sL "${URL_NM_CONF}" > "${FILE_NM_CONF}"
if [ ! -f "$FILE_NM_CONNECTION" ]; then
    curl -sL "${URL_NM_CONNECTION}" > "${FILE_NM_CONNECTION}"
fi
info "A reiniciar o NetworkManager"
systemctl restart "${SERVICE_NM}"

# Parse command line parameters
while [[ $# -gt 0 ]]; do
    arg="$1"

    case $arg in
        -m|--machine)
            MACHINE=$2
            shift
            ;;
        -d|--data-share)
            DATA_SHARE=$2
            shift
            ;;
        -p|--prefix)
            PREFIX=$2
            shift
            ;;
        -s|--sysconfdir)
            SYSCONFDIR=$2
            shift
            ;;
        *)
            error "opção não reconhecida $1"
            ;;
    esac
    shift
done

PREFIX=${PREFIX:-/usr}
SYSCONFDIR=${SYSCONFDIR:-/etc}
DATA_SHARE=${DATA_SHARE:-$PREFIX/share/hassio}
CONFIG=$SYSCONFDIR/hassio.json

# Generate hardware options
case $ARCH in
    "i386" | "i686")
        MACHINE=${MACHINE:=qemux86}
        HASSIO_DOCKER="$DOCKER_REPO/i386-hassio-supervisor"
    ;;
    "x86_64")
        MACHINE=${MACHINE:=qemux86-64}
        HASSIO_DOCKER="$DOCKER_REPO/amd64-hassio-supervisor"
    ;;
    "arm" |"armv6l")
        if [ -z $MACHINE ]; then
            error "Por favor, configura a máquina para $ARCH"
        fi
        HASSIO_DOCKER="$DOCKER_REPO/armhf-hassio-supervisor"
    ;;
    "armv7l")
        if [ -z $MACHINE ]; then
            error "Por favor, configura a máquina para $ARCH"
        fi
        HASSIO_DOCKER="$DOCKER_REPO/armv7-hassio-supervisor"
    ;;
    "aarch64")
        if [ -z $MACHINE ]; then
            error "Por favor, configura a máquina para $ARCH"
        fi
        HASSIO_DOCKER="$DOCKER_REPO/aarch64-hassio-supervisor"
    ;;
    *)
        error "$ARCH desconhecido!"
    ;;
esac

if [[ ! "${MACHINE}" =~ ^(intel-nuc|odroid-c2|odroid-n2|odroid-xu|qemuarm|qemuarm-64|qemux86|qemux86-64|raspberrypi|raspberrypi2|raspberrypi3|raspberrypi4|raspberrypi3-64|raspberrypi4-64|tinker)$ ]]; then
    error "Tipo de máquina desconhecido ${MACHINE}!"
fi

### Main

# Init folders
if [ ! -d "$DATA_SHARE" ]; then
    mkdir -p "$DATA_SHARE"
fi

# Read infos from web
HASSIO_VERSION=$(curl -s $URL_VERSION | jq -e -r '.supervisor')

##
# Write configuration
cat > "$CONFIG" <<- EOF
{
    "supervisor": "${HASSIO_DOCKER}",
    "machine": "${MACHINE}",
    "data": "${DATA_SHARE}"
}
EOF

##
# Pull supervisor image
info "A instalar o container do Supervisor no Docker"
docker pull "$HASSIO_DOCKER:$HASSIO_VERSION" > /dev/null
docker tag "$HASSIO_DOCKER:$HASSIO_VERSION" "$HASSIO_DOCKER:latest" > /dev/null

##
# Install Hass.io Supervisor
info "A instalar os scripts de inicialização do Supervisor"
curl -sL ${URL_BIN_HASSIO} > "${PREFIX}/sbin/hassio-supervisor"
curl -sL ${URL_SERVICE_HASSIO} > "${SYSCONFDIR}/systemd/system/hassio-supervisor.service"

sed -i "s,%%HASSIO_CONFIG%%,${CONFIG},g" "${PREFIX}"/sbin/hassio-supervisor
sed -i -e "s,%%BINARY_DOCKER%%,${BINARY_DOCKER},g" \
       -e "s,%%SERVICE_DOCKER%%,${SERVICE_DOCKER},g" \
       -e "s,%%BINARY_HASSIO%%,${PREFIX}/sbin/hassio-supervisor,g" \
       "${SYSCONFDIR}/systemd/system/hassio-supervisor.service"

chmod a+x "${PREFIX}/sbin/hassio-supervisor"
systemctl enable hassio-supervisor.service > /dev/null 2>&1;

#
# Install Hass.io AppArmor
info "A instalar os scripts do AppArmor"
mkdir -p "${DATA_SHARE}/apparmor"
curl -sL ${URL_BIN_APPARMOR} > "${PREFIX}/sbin/hassio-apparmor"
curl -sL ${URL_SERVICE_APPARMOR} > "${SYSCONFDIR}/systemd/system/hassio-apparmor.service"
curl -sL ${URL_APPARMOR_PROFILE} > "${DATA_SHARE}/apparmor/hassio-supervisor"

sed -i "s,%%HASSIO_CONFIG%%,${CONFIG},g" "${PREFIX}/sbin/hassio-apparmor"
sed -i -e "s,%%SERVICE_DOCKER%%,${SERVICE_DOCKER},g" \
    -e "s,%%HASSIO_APPARMOR_BINARY%%,${PREFIX}/sbin/hassio-apparmor,g" \
    "${SYSCONFDIR}/systemd/system/hassio-apparmor.service"

chmod a+x "${PREFIX}/sbin/hassio-apparmor"
systemctl enable hassio-apparmor.service > /dev/null 2>&1;
systemctl start hassio-apparmor.service


##
# Init system
info "A iniciar o Home Assistant Supervised"
systemctl start hassio-supervisor.service

##
# Setup CLI
info "A instalar a linha de comandos 'ha'"
curl -sL ${URL_HA} > "${PREFIX}/bin/ha"
chmod a+x "${PREFIX}/bin/ha"

info
info "O Home Assistant Supervised está instalado!"
info "O primeiro arranque irá demorar um pouco, quando estiver pronto poderá ser acedido pelo endereço:"
info "http://${IP_ADDRESS}:8123"
info
info "Se precisares de ajuda usa um dos seguintes links:"
info
info "https://forum.cpha.pt ou https://discord.gg/Mh9mTEA"
info
info by CPHA - Comunidade Portuguesa de Home Assistant
info


####
