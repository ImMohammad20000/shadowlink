#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
ENV_FILE="$SCRIPT_DIR/env"
SAMPLE_CONFIG="$SCRIPT_DIR/sample_config.json"
TUNNEL_JSON="$SCRIPT_DIR/tunnel.json"
BUNDLED_XRAY_ROOT="$SCRIPT_DIR/.xray-linux"

if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  GOLD=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  NC=$(tput sgr0)
else
  RED=""
  GREEN=""
  GOLD=""
  BLUE=""
  NC=""
fi

adapter_names=()
adapter_ips=()
selected_index=0
prompt_value=""

starlink_nic=""
starlink_ipv4=""
iran_internet_nic=""
iran_internet_ipv4=""
bridge_server=""
uuid=""
encryption=""

print_banner() {
  printf '%b\n' "${RED}                                                  				${NC}"
  printf '%b\n' "${RED}    ▄▄▄▄▄    ▄  █ ██   ██▄   ████▄   ▄ ▄   █    ▄█    ▄   █  █▀ ${NC}"
  printf '%b\n' "${RED}   █     ▀▄ █   █ █ █  █  █  █   █  █   █  █    ██     █  █▄█   ${NC}"
  printf '%b\n' "${RED} ▄  ▀▀▀▀▄   ██▀▀█ █▄▄█ █   █ █   █ █ ▄   █ █    ██ ██   █ █▀▄   ${NC}"
  printf '%b\n' "${RED}  ▀▄▄▄▄▀    █   █ █  █ █  █  ▀████ █  █  █ ███▄ ▐█ █ █  █ █  █  ${NC}"
  printf '%b\n' "${RED}               █     █ ███▀         █ █ █      ▀ ▐ █  █ █   █   ${NC}"
  printf '%b\n' "${RED}              ▀     █                ▀ ▀           █   ██  ▀    ${NC}"
  printf '%b\n' "${RED}                   ▀                                            ${NC}"
}

trim() {
  local value=$1
  value=${value%$'\r'}
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s' "$value"
}

add_adapter() {
  local name=$1
  local ip=$2
  local i

  [[ -z $name || -z $ip ]] && return

  for ((i = 0; i < ${#adapter_names[@]}; i++)); do
    if [[ ${adapter_names[i]} == "$name" ]]; then
      adapter_ips[i]=$ip
      return
    fi
  done

  adapter_names+=("$name")
  adapter_ips+=("$ip")
}

load_linux_adapters() {
  while IFS=$'\t' read -r name ip; do
    name=${name%%@*}
    add_adapter "$name" "$ip"
  done < <(ip -o -4 addr show up scope global | awk '{split($4, ipv4, "/"); print $2 "\t" ipv4[1]}' | sort -u)
}

load_bsd_adapters() {
  local iface ip

  for iface in $(ifconfig -l); do
    [[ $iface == lo0 || $iface == lo ]] && continue

    ip=""
    if command -v ipconfig >/dev/null 2>&1; then
      ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    fi

    if [[ -z $ip ]]; then
      ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" { print $2; exit }')
    fi

    add_adapter "$iface" "$ip"
  done
}

refresh_system_adapters() {
  adapter_names=()
  adapter_ips=()

  if command -v ip >/dev/null 2>&1; then
    load_linux_adapters
  elif command -v ifconfig >/dev/null 2>&1; then
    load_bsd_adapters
  else
    printf '%b\n' "${RED}Error: neither 'ip' nor 'ifconfig' is available for adapter discovery.${NC}"
    exit 1
  fi

  if [[ ${#adapter_names[@]} -eq 0 ]]; then
    printf '%b\n' "${RED}No network adapters with IPv4 addresses were found.${NC}"
    exit 1
  fi

  printf '%b\n\n' "${GREEN}DONE!${NC}"
}

adapter_matches() {
  local nic=$1
  local ipv4=$2
  local i

  for ((i = 0; i < ${#adapter_names[@]}; i++)); do
    if [[ ${adapter_names[i]} == "$nic" && ${adapter_ips[i]} == "$ipv4" ]]; then
      return 0
    fi
  done

  return 1
}

resolve_xray_bin() {
  local arch
  local asset_path
  local extract_dir
  local xray_bin

  if [[ -n ${XRAY_BIN:-} ]]; then
    if [[ -x $XRAY_BIN ]]; then
      printf '%s' "$XRAY_BIN"
      return 0
    fi

    printf '%b\n' "${RED}Error: XRAY_BIN is set but is not executable: ${XRAY_BIN}${NC}"
    exit 1
  fi

  arch=$(uname -m)
  case "$arch" in
    x86_64) asset_path="$REPO_ROOT/server/assets/xray-core-amd64.tar.gz" ;;
    aarch64|arm64) asset_path="$REPO_ROOT/server/assets/xray-core-arm64.tar.gz" ;;
    *) asset_path="" ;;
  esac

  if [[ -n $asset_path ]]; then
    xray_bin="$BUNDLED_XRAY_ROOT/xray-core/xray"
    if [[ ! -x $xray_bin ]]; then
      [[ -f $asset_path ]] || {
        printf '%b\n' "${RED}Error: bundled xray asset not found at ${asset_path}.${NC}"
        exit 1
      }

      extract_dir="$BUNDLED_XRAY_ROOT.tmp"
      rm -rf "$extract_dir"
      mkdir -p "$extract_dir"
      tar -xzf "$asset_path" -C "$extract_dir"
      rm -rf "$BUNDLED_XRAY_ROOT"
      mv "$extract_dir" "$BUNDLED_XRAY_ROOT"
      chmod +x "$xray_bin"
    fi

    if [[ -x $xray_bin ]]; then
      printf '%s' "$xray_bin"
      return 0
    fi
  fi

  if [[ -x $SCRIPT_DIR/xray ]]; then
    printf '%s' "$SCRIPT_DIR/xray"
    return 0
  fi

  if command -v xray >/dev/null 2>&1; then
    command -v xray
    return 0
  fi

  printf '%b\n' "${RED}Error: Unix xray binary not found. No supported bundled Linux asset was usable, and no override was found in XRAY_BIN, client/xray, or PATH.${NC}"
  exit 1
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

generate_tunnel_config() {
  local starlink_escaped
  local iran_escaped
  local bridge_escaped
  local uuid_escaped
  local encryption_escaped

  [[ -f $SAMPLE_CONFIG ]] || {
    printf '%b\n' "${RED}Error: sample config not found at ${SAMPLE_CONFIG}.${NC}"
    exit 1
  }

  starlink_escaped=$(escape_sed_replacement "$starlink_ipv4")
  iran_escaped=$(escape_sed_replacement "$iran_internet_ipv4")
  bridge_escaped=$(escape_sed_replacement "$bridge_server")
  uuid_escaped=$(escape_sed_replacement "$uuid")
  encryption_escaped=$(escape_sed_replacement "$encryption")

  sed \
    -e "s/starlink_ipv4/${starlink_escaped}/g" \
    -e "s/iran_internet_ipv4/${iran_escaped}/g" \
    -e "s/bridge_server/${bridge_escaped}/g" \
    -e "s/uuid/${uuid_escaped}/g" \
    -e "s/encryption_key/${encryption_escaped}/g" \
    "$SAMPLE_CONFIG" >"$TUNNEL_JSON"
}

launch_tunnel() {
  local xray_bin

  generate_tunnel_config

  if [[ ! -f $TUNNEL_JSON ]]; then
    printf '%b\n' "${RED}tunnel.json not found.${NC}"
    exit 1
  fi

  xray_bin=$(resolve_xray_bin)
  printf '%b\n\n' "Launching ${RED}Shadowlink${NC} Tunnel:"
  "$xray_bin" run -c "$TUNNEL_JSON"
}

load_env_file() {
  local key value

  starlink_nic=""
  starlink_ipv4=""
  iran_internet_nic=""
  iran_internet_ipv4=""
  bridge_server=""
  uuid=""
  encryption=""

  while IFS='=' read -r key value || [[ -n $key ]]; do
    key=$(trim "$key")
    value=$(trim "$value")

    case "$key" in
      starlink_nic) starlink_nic=$value ;;
      starlink_ipv4) starlink_ipv4=$value ;;
      iran_internet_nic) iran_internet_nic=$value ;;
      iran_internet_ipv4) iran_internet_ipv4=$value ;;
      bridge_server) bridge_server=$value ;;
      uuid) uuid=$value ;;
      encryption) encryption=$value ;;
    esac
  done <"$ENV_FILE"
}

check_env_file() {
  load_env_file

  if [[ -z $bridge_server ]]; then
    printf '%b\n' "${RED}Bridge Server entry is missing or empty in the env file. Please enter it again.${NC}"
    return 1
  fi

  if [[ -z $uuid ]]; then
    printf '%b\n' "${RED}UUID entry is missing or empty in the env file. Please enter it again.${NC}"
    return 1
  fi

  if [[ -z $encryption ]]; then
    printf '%b\n' "${RED}VLESS encryption entry is missing or empty in the env file. Please enter it again.${NC}"
    return 1
  fi

  if ! adapter_matches "$starlink_nic" "$starlink_ipv4"; then
    printf '%b\n' "${RED}Starlink NIC and IPv4 do not match. Please select again.${NC}"
    return 1
  fi

  if ! adapter_matches "$iran_internet_nic" "$iran_internet_ipv4"; then
    printf '%b\n' "${RED}Iran Internet NIC and IPv4 do not match. Please select again.${NC}"
    return 1
  fi

  printf '%b\n\n' "${GREEN}Env file entries match the system's network adapters and IPs.${NC}"
  launch_tunnel
}

prompt_for_adapter() {
  local label=$1
  local choice
  local i

  printf '\nSelect the network adapter for "%b%s%b":\n\n' "$GOLD" "$label" "$NC"
  for ((i = 0; i < ${#adapter_names[@]}; i++)); do
    printf '%d. %s (%s)\n' "$((i + 1))" "${adapter_names[i]}" "${adapter_ips[i]}"
  done
  printf '\n'

  while true; do
    read -r -p "Choose an option: " choice
    if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#adapter_names[@]})); then
      selected_index=$choice
      return 0
    fi

    printf '%s\n' "Invalid selection. Please enter a valid number from the list above."
  done
}

prompt_for_text() {
  local label=$1
  local value=""

  while [[ -z $value ]]; do
    printf '\n'
    read -r -p "$label" value
    value=$(trim "$value")

    if [[ -z $value ]]; then
      printf '%s\n' "Please enter a valid value."
    fi
  done

  prompt_value=$value
}

write_env_file() {
  {
    printf 'starlink_nic=%s\n' "$starlink_nic"
    printf 'starlink_ipv4=%s\n' "$starlink_ipv4"
    printf 'iran_internet_nic=%s\n' "$iran_internet_nic"
    printf 'iran_internet_ipv4=%s\n' "$iran_internet_ipv4"
    printf 'bridge_server=%s\n' "$bridge_server"
    printf 'uuid=%s\n' "$uuid"
    printf 'encryption=%s\n' "$encryption"
  } >"$ENV_FILE"

  printf '\n%b\n\n' "${BLUE}Selections and IP addresses saved to \"env\" file.${NC}"
}

main() {
  print_banner
  printf '\nFetching system network information\n'
  refresh_system_adapters

  if [[ -f $ENV_FILE ]]; then
    if check_env_file; then
      exit 0
    fi
  fi

  prompt_for_adapter "Starlink"
  starlink_nic=${adapter_names[selected_index - 1]}
  starlink_ipv4=${adapter_ips[selected_index - 1]}
  printf '%s\n' "Starlink adapter selected: ${BLUE}${starlink_nic}${NC}"
  printf '%s\n' "Starlink IPv4 address: ${BLUE}${starlink_ipv4}${NC}"

  prompt_for_adapter "Iran Internet"
  iran_internet_nic=${adapter_names[selected_index - 1]}
  iran_internet_ipv4=${adapter_ips[selected_index - 1]}
  printf '%s\n' "Iran Internet adapter selected: ${BLUE}${iran_internet_nic}${NC}"
  printf '%s\n' "Iran Internet IPv4 address: ${BLUE}${iran_internet_ipv4}${NC}"

  prompt_for_text "Enter Bridge Server domain or IP address: "
  bridge_server=$prompt_value
  prompt_for_text "Please enter the UUID: "
  uuid=$prompt_value
  prompt_for_text "Please enter the VLESS encryption key: "
  encryption=$prompt_value

  write_env_file
  launch_tunnel
}

main "$@"
