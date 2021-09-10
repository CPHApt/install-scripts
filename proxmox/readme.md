O repositório Proxmox contém os seguintes scripts:

#### Script `proxmox_prepare.sh`
- Comando de instalação:
  - `bash -c "$(wget -qLO - https://raw.githubusercontent.com/CPHApt/install-scripts/master/proxmox/proxmox_prepare.sh)"`
- Retira o repositório comercial,
- Activa o repositório da comunidade,
- Actualiza o Proxmox,
- Retira o popup que avisa sobre não existir uma subscrição

#### Script `proxmox_black_theme.sh`
- Comando de instalação:
  - `bash -c "$(wget -qLO - https://raw.githubusercontent.com/CPHApt/install-scripts/master/proxmox/proxmox_black_theme.sh)"`
- Descarrega o ficheiro de instalação
- Corre o script
