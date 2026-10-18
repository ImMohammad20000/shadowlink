#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
BLUE=$(tput setaf 4)
GOLD=$(tput setaf 3)
NC=$(tput sgr0)

UUID=""
CUSTOM_UUID=""
VLESS_AUTHENTICATION_LABEL="Authentication: X25519, not Post-Quantum"
VLESS_DECRYPTION=""
VLESS_ENCRYPTION=""
XUI_DB="/etc/x-ui/x-ui.db"
XUI_JSON="/opt/shadowlink/3x-ui.json"
SQLITE_BIN="/opt/shadowlink/sqlite3/sqlite3"
TUNNEL_JSON="/opt/shadowlink/xray-core/tunnel_server.json"
IPV4=""
release=""
PANEL_USERNAME="shadowlink"
PANEL_PASSWORD=""

print_usage() {
  echo "Usage: $0 [--uuid <uuid>]"
}

validate_uuid() {
  if [[ ! $1 =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    echo "${RED}Invalid UUID format:${NC} $1"
    print_usage
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --uuid)
        if [[ $# -lt 2 ]]; then
          echo "${RED}Missing value for --uuid${NC}"
          print_usage
          exit 1
        fi
        CUSTOM_UUID="$2"
        validate_uuid "$CUSTOM_UUID"
        shift 2
        ;;
      --uuid=*)
        CUSTOM_UUID="${1#*=}"
        validate_uuid "$CUSTOM_UUID"
        shift
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        echo "${RED}Unknown option:${NC} $1"
        print_usage
        exit 1
        ;;
    esac
  done
}

resolve_ipv4() {
  if [[ -z $IPV4 ]]; then
    IPV4=$(hostname -I | awk '{print $1}')
  fi
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

extract_vlessenc_value() {
  local vlessenc_output=$1
  local field_name=$2

  printf '%s\n' "$vlessenc_output" | awk -F'"' -v auth_label="$VLESS_AUTHENTICATION_LABEL" -v field_name="$field_name" '
    $0 == auth_label { in_block = 1; next }
    in_block && /^Authentication:/ { exit }
    in_block && $2 == field_name { print $4; exit }
  '
}

generate_vless_encryption_keys() {
  local vlessenc_output=""

  vlessenc_output=$(/opt/shadowlink/xray-core/xray vlessenc) || {
    echo "${RED}Failed to generate VLESS encryption keys with xray vlessenc!${NC}"
    exit 1
  }

  VLESS_DECRYPTION=$(extract_vlessenc_value "$vlessenc_output" "decryption")
  VLESS_ENCRYPTION=$(extract_vlessenc_value "$vlessenc_output" "encryption")

  if [[ -z $VLESS_DECRYPTION || -z $VLESS_ENCRYPTION ]]; then
    echo "${RED}Failed to parse X25519 VLESS encryption keys from xray vlessenc output!${NC}"
    exit 1
  fi
}

detect_xui_arch() {
  ARCH=$(uname -m)
  case "${ARCH}" in
    x86_64 | x64 | amd64) XUI_ARCH="amd64" ;;
    i*86 | x86) XUI_ARCH="386" ;;
    armv8* | armv8 | arm64 | aarch64) XUI_ARCH="arm64" ;;
    armv7* | armv7) XUI_ARCH="armv7" ;;
    armv6* | armv6) XUI_ARCH="armv6" ;;
    armv5* | armv5) XUI_ARCH="armv5" ;;
    s390x) XUI_ARCH="s390x" ;;
    *) XUI_ARCH="amd64" ;;
  esac
}

detect_release() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
  elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
  else
    echo "Failed to detect OS"
    exit 1
  fi
}

install_xui() {
  local xui_asset=""
  local service_file=""
  local xui_version=""

  detect_xui_arch
  detect_release

  case "$XUI_ARCH" in
    amd64) xui_asset="$SCRIPT_DIR/assets/3x-ui-amd64.tar.gz" ;;
    arm64) xui_asset="$SCRIPT_DIR/assets/3x-ui-arm64.tar.gz" ;;
    *)
      echo "${RED}No bundled 3x-ui asset is available for architecture: ${XUI_ARCH}${NC}"
      exit 1
      ;;
  esac

  cd /root/ || exit 1
  rm -rf x-ui/ /usr/local/x-ui/ /usr/bin/x-ui
  tar -xzf "$xui_asset" || exit 1
  [[ -s x-ui/x-ui ]] || { echo "${RED}3x-ui archive is missing its binary.${NC}"; exit 1; }
  chmod +x x-ui/x-ui x-ui/bin/xray-linux-*
  xui_version=$(x-ui/x-ui -v) || exit 1
  [[ "$xui_version" =~ ^([3-9]|[1-9][0-9])\. ]] || {
    echo "${RED}3x-ui v3 or newer is required (found $xui_version).${NC}"
    exit 1
  }

  if [[ "$release" == "ubuntu" || "$release" == "debian" || "$release" == "armbian" ]]; then
    service_file="x-ui.service.debian"
  elif [[ "$release" == "arch" || "$release" == "archlinux" || "$release" == "manjaro" ]]; then
    service_file="x-ui.service.arch"
  else
    service_file="x-ui.service.rhel"
  fi

  if [[ -f "x-ui/$service_file" ]]; then
    cp -f "x-ui/$service_file" /etc/systemd/system/x-ui.service
  else
    cp -f "$SCRIPT_DIR/assets/$service_file" /etc/systemd/system/x-ui.service || exit 1
  fi
  if [[ -f "$SCRIPT_DIR/assets/x-ui.sh" ]]; then
    cp -f "$SCRIPT_DIR/assets/x-ui.sh" /usr/bin/x-ui || exit 1
  elif [[ -f x-ui/x-ui.sh ]]; then
    cp -f x-ui/x-ui.sh /usr/bin/x-ui || exit 1
  else
    echo "${RED}3x-ui management script is missing from the bundle.${NC}"
    exit 1
  fi
  chmod +x /usr/bin/x-ui
  mv x-ui/ /usr/local/
}

check_root_user() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as ${RED}root!${NC}"
    exit 1
  fi
}

shadowlink_check() {
    if systemctl list-units --full -all | grep -q "shadowlink.service"; then
        return 1
    fi
    return 0
}

extract_files() {
    if [ ! -d "/opt/shadowlink" ]; then
        mkdir -p /opt/shadowlink || { echo -e "${RED}Failed to create /opt/shadowlink directory!${NC}"; exit 1; }
    fi

    if [ ! -d "/etc/x-ui" ]; then
        mkdir -p -m 700 /etc/x-ui || { echo -e "${RED}Failed to create /etc/x-ui directory!${NC}"; exit 1; }
    fi

    CPU_ARCH=$(uname -m)
    case $CPU_ARCH in
        "x86_64" | "amd64" | "x64")
            tar -xzf "$SCRIPT_DIR/assets/xray-core-amd64.tar.gz" -C /opt/shadowlink
            tar -xzf "$SCRIPT_DIR/assets/sqlite3-amd64.tar.gz" -C /opt/shadowlink
            ;;
        "aarch64" | "arm64")
            tar -xzf "$SCRIPT_DIR/assets/xray-core-arm64.tar.gz" -C /opt/shadowlink
            tar -xzf "$SCRIPT_DIR/assets/sqlite3-arm64.tar.gz" -C /opt/shadowlink
            ;;
        *)
            echo "${RED}Unsupported CPU architecture: $CPU_ARCH${NC}"
            exit 1
            ;;
    esac

	cp -f "$SCRIPT_DIR/assets/3x-ui.json.sample" /opt/shadowlink/3x-ui.json
	cp -f "$SCRIPT_DIR/assets/tunnel_server.json.sample" /opt/shadowlink/xray-core/tunnel_server.json
	cp -f "$SCRIPT_DIR/assets/shadowlink_service.sh" /opt/shadowlink/shadowlink_service.sh
	chmod -R +x /opt/shadowlink

    install_xui
}

db_update() {
    # 3x-ui creates and migrates its own schema. Its template setting is still
    # stored in SQLite; readfile preserves quotes and backslashes in the JSON.
    "$SQLITE_BIN" -bail "$XUI_DB" "BEGIN;
      UPDATE settings SET value=CAST(readfile('$XUI_JSON') AS TEXT) WHERE key='xrayTemplateConfig';
      INSERT INTO settings (key, value)
        SELECT 'xrayTemplateConfig', CAST(readfile('$XUI_JSON') AS TEXT)
        WHERE NOT EXISTS (SELECT 1 FROM settings WHERE key='xrayTemplateConfig');
      COMMIT;" || exit 1
}

configure_xui() {
    PANEL_PASSWORD=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    [[ ${#PANEL_PASSWORD} -eq 32 ]] || { echo "${RED}Failed to generate panel password.${NC}"; exit 1; }
    # The v3 CLI initializes the current schema and hashes the password.
    /usr/local/x-ui/x-ui setting -username "$PANEL_USERNAME" -password "$PANEL_PASSWORD" -port 7092 -webBasePath /shadowlink/ || exit 1
    [[ -s "$XUI_DB" ]] || { echo "${RED}3x-ui did not create its database.${NC}"; exit 1; }
}

shadowlink_service() {
    cat <<EOL > /etc/systemd/system/shadowlink.service
[Unit]
Description=Shadowlink Service (Xray-Core Tunnel)
After=network.target

[Service]
ExecStart=/opt/shadowlink/shadowlink_service.sh
WorkingDirectory=/opt/shadowlink
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL

    if [ $? -ne 0 ]; then
        echo "${RED}Failed to create shadowlink.service!${NC}"
        exit 1
    fi

    systemctl daemon-reload || { echo "${RED}Failed to reload systemd daemon!${NC}"; exit 1; }

    systemctl enable shadowlink.service || { echo "${RED}Failed to enable shadowlink service!${NC}"; exit 1; }
    systemctl enable x-ui || { echo "${RED}Failed to enable x-ui service!${NC}"; exit 1; }
}

shadowlink_remover() {
    systemctl stop shadowlink.service 2>/dev/null || true
    systemctl disable shadowlink.service 2>/dev/null || true
    systemctl stop x-ui 2>/dev/null || true
    systemctl disable x-ui 2>/dev/null || true
    rm -f /etc/systemd/system/shadowlink.service
    rm -f /etc/systemd/system/x-ui.service
    systemctl daemon-reload
    rm -rf /opt/shadowlink
    rm -rf /etc/x-ui
    rm -rf /etc/3x-ui
    rm -rf /usr/local/x-ui
    rm -f /usr/bin/x-ui
    rm -rf /root/x-ui
}

uuid_setup() {
  local escaped_uuid=""
  local escaped_vless_decryption=""

  if [[ -n $CUSTOM_UUID ]]; then
    UUID="$CUSTOM_UUID"
  else
    UUID=$(/opt/shadowlink/xray-core/xray uuid)
  fi

  generate_vless_encryption_keys

  escaped_uuid=$(escape_sed_replacement "$UUID")
  escaped_vless_decryption=$(escape_sed_replacement "$VLESS_DECRYPTION")

  sed -i "s|\"reverse_tunnel_uuid\"|\"$escaped_uuid\"|g" "$TUNNEL_JSON"
  sed -i "s|\"reverse_tunnel_uuid\"|\"$escaped_uuid\"|g" "$XUI_JSON"
  sed -i "s|\"reverse_tunnel_decryption\"|\"$escaped_vless_decryption\"|" "$TUNNEL_JSON"
}

print_client_credentials() {
  echo "Please save these reverse tunnel credentials and pass them to the client (PC with the ${GOLD}STARLINK${NC}):"
  echo
  echo "${RED}UUID${NC}= ${GREEN}$UUID${NC}"
  echo "${RED}VLESS Auth${NC}= ${GREEN}X25519 (not Post-Quantum)${NC}"
  echo "${RED}VLESS Encryption${NC}= ${GREEN}$VLESS_ENCRYPTION${NC}"
  echo
}

parse_args "$@"
check_root_user
clear
echo
echo
echo "${RED}   ▄▄▄▄▄    ▄  █ ██   ██▄   ████▄   ▄ ▄   █    ▄█    ▄   █  █▀ "
echo "  █     ▀▄ █   █ █ █  █  █  █   █  █   █  █    ██     █  █▄█   "
echo "▄  ▀▀▀▀▄   ██▀▀█ █▄▄█ █   █ █   █ █ ▄   █ █    ██ ██   █ █▀▄   "
echo " ▀▄▄▄▄▀    █   █ █  █ █  █  ▀████ █  █  █ ███▄ ▐█ █ █  █ █  █   "
echo "              █     █ ███▀         █ █ █      ▀ ▐ █  █ █   █   "
echo "             ▀     █                ▀ ▀           █   ██  ▀    "
echo "                  ▀                                            ${NC}"
echo
echo
echo "Please choose an option:"
echo
echo "1. ${GOLD}Setup${NC}"
echo "2. ${GOLD}Reset Setup${NC}"
echo "3. ${GOLD}Uninstall${NC}"
echo
while true; do
    read -p "Enter your choice (1-3): " choice

    case $choice in
        1)
            shadowlink_check
            if [ $? -eq 1 ]; then
				echo "${RED}Shadowlink${NC} is already installed on this system. You can choose Reset or Uninstall."
                continue
            fi
			if [[ -e "$XUI_DB" || -e /usr/local/x-ui ]]; then
				echo "${RED}An existing 3x-ui installation was found. Back it up or use a separate server for Shadowlink.${NC}"
				break
			fi
			echo
			echo "Extracting Assets..."
            extract_files
			echo "${GREEN}DONE!${NC}"
			if [[ -n $CUSTOM_UUID ]]; then
				echo "Using custom UUID..."
			else
				echo "Generating new UUID..."
			fi
			uuid_setup
			echo "${GREEN}DONE!${NC}"
			echo "Configuring 3x-ui..."
			configure_xui
			echo "Updating Xray template..."
			db_update
			echo "${GREEN}DONE!${NC}"
			echo "Creating new systemd service..."
			shadowlink_service
			echo "${GREEN}DONE!${NC}"
			echo "Starting ${RED}x-ui${NC}..."
			systemctl restart x-ui
			echo "${GREEN}DONE!${NC}"
			echo "Starting ${RED}Shadowlink${NC}..."
			systemctl restart shadowlink.service
			echo "${GREEN}DONE!${NC}"
			resolve_ipv4
			echo
			echo "${GOLD}Panel Info${NC}:"
			echo "${GREEN}Address${NC}: http://$IPV4:7092/shadowlink"
			echo "${GREEN}Username${NC}: $PANEL_USERNAME"
			echo "${GREEN}Password${NC}: $PANEL_PASSWORD"
				echo 
				echo "${GOLD}Save the generated panel password; it is shown only during setup.${NC}"
	            		echo
				print_client_credentials
            break
            ;;
        2)
			shadowlink_check
			if [ $? -eq 0 ]; then
				echo "${RED}Shadowlink${NC} is not installed!"
				continue
				echo
			else
				read -p "This will remove ${RED}Shadowlink${NC} and its associated files (DB included)? (y/n): " confirm
				if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
					shadowlink_remover
					echo
					echo "Extracting Assets..."
					extract_files
					echo "${GREEN}DONE!${NC}"
					if [[ -n $CUSTOM_UUID ]]; then
						echo "Using custom UUID..."
					else
						echo "Generating new UUID..."
					fi
					uuid_setup
					echo "${GREEN}DONE!${NC}"
					echo "Configuring 3x-ui..."
					configure_xui
					echo "Updating Xray template..."
					db_update
					echo "${GREEN}DONE!${NC}"
					echo "Creating new systemd service..."
					shadowlink_service
					echo "${GREEN}DONE!${NC}"
					echo "Starting ${RED}x-ui${NC}..."
					systemctl restart x-ui
					echo "${GREEN}DONE!${NC}"
					echo "Starting ${RED}Shadowlink${NC}..."
					systemctl restart shadowlink.service
					echo "${GREEN}DONE!${NC}"
					resolve_ipv4
					echo
					echo "${GOLD}Panel Info${NC}:"
					echo "${GREEN}Address${NC}: http://$IPV4:7092/shadowlink"
					echo "${GREEN}Username${NC}: $PANEL_USERNAME"
					echo "${GREEN}Password${NC}: $PANEL_PASSWORD"
						echo 
						echo "${GOLD}Save the generated panel password; it is shown only during setup.${NC}"
						echo 
						print_client_credentials
						break
				else
					echo
					echo "${GREEN}Aborted!${NC} ${RED}Shadowlink${NC} has not been removed."
					echo
				fi
			fi
			break
			;;
        3)
			shadowlink_check
			if [ $? -eq 0 ]; then
				echo "${RED}Shadowlink${NC} is not installed!"
				continue
				echo
			else
				read -p "Are you sure you want to remove ${RED}Shadowlink${NC} and its associated files (DB included)? (y/n): " confirm
				if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
					shadowlink_remover
					echo
					echo "${RED}Shadowlink${NC} has been ${RED}REMOVED!${NC}"
					echo
				else
					echo
					echo "${GREEN}Aborted!${NC} ${RED}Shadowlink${NC} has not been removed."
					echo
				fi
			fi
			break
			;;
        *)
            echo "Invalid option. Please enter a number between 1 and 3."
            ;;
    esac
done
