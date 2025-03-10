#!/usr/bin/env bash

set -e
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh

[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"

# Shows title
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="${ARC_TITLE}"
printf "\033[1;30m%*s\n" ${COLUMNS} ""
printf "\033[1;30m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;30m%*s\033[0m\n" ${COLUMNS} ""

# If user config file not exists, initialize it
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
fi
initConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
initConfigKey "model" "" "${USER_CONFIG_FILE}"
initConfigKey "productver" "" "${USER_CONFIG_FILE}"
initConfigKey "layout" "qwertz" "${USER_CONFIG_FILE}"
initConfigKey "keymap" "de" "${USER_CONFIG_FILE}"
initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
initConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
initConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
initConfigKey "arc" "{}" "${USER_CONFIG_FILE}"
initConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.sn" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.ipv6" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.emmcboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.offline" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.directboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.bootipwait" "20" "${USER_CONFIG_FILE}"
initConfigKey "arc.kernelload" "power" "${USER_CONFIG_FILE}"
initConfigKey "arc.kernelpanic" "5" "${USER_CONFIG_FILE}"
initConfigKey "arc.macsys" "hardware" "${USER_CONFIG_FILE}"
initConfigKey "arc.odp" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.hddsort" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
initConfigKey "device" "{}" "${USER_CONFIG_FILE}"
initConfigKey "ip" "{}" "${USER_CONFIG_FILE}"
initConfigKey "netmask" "{}" "${USER_CONFIG_FILE}"
initConfigKey "mac" "{}" "${USER_CONFIG_FILE}"
initConfigKey "static" "{}" "${USER_CONFIG_FILE}"

# Init Network
ETHX=$(ls /sys/class/net/ | grep -v lo) || true
MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
# Write Mac to config
N=0
for ETH in ${ETHX}; do
  MACR="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
  initConfigKey "mac.${ETH}" "${MACR}" "${USER_CONFIG_FILE}"
  if [ "${MACSYS}" = "custom" ]; then
    MACA="$(readConfigKey "mac.${ETH}" "${USER_CONFIG_FILE}")"
    if [[ -n "${MACA}" && "${MACA}" != "${MACR}" ]]; then
      MAC="${MACA:0:2}:${MACA:2:2}:${MACA:4:2}:${MACA:6:2}:${MACA:8:2}:${MACA:10:2}"
      echo "Setting ${ETH} MAC to ${MAC}"
      ip link set dev ${ETH} address "${MAC}" >/dev/null 2>&1 &&
      (/etc/init.d/S41dhcpcd restart >/dev/null 2>&1 &) || true
      sleep 2
    fi
    echo
  fi
  ethtool -s ${ETH} wol g 2>/dev/null
  N=$((${N} + 1))
done
# Write NIC Amount to config
writeConfigKey "device.nic" "${N}" "${USER_CONFIG_FILE}"
# No network devices
[ ${N} -le 0 ] && die "No NIC found! - Loader does not work without Network connection."

# Get the VID/PID if we are in USB
VID="0x46f4"
PID="0x0001"
BUS=$(getBus "${LOADER_DISK}")

if [ "${BUS}" = "usb" ]; then
  VID="0x$(udevadm info --query property --name "${LOADER_DISK}" | grep ID_VENDOR_ID | cut -d= -f2)"
  PID="0x$(udevadm info --query property --name "${LOADER_DISK}" | grep ID_MODEL_ID | cut -d= -f2)"
elif [[ "${BUS}" != "sata" && "${BUS}" != "scsi" && "${BUS}" != "nvme" && "${BUS}" != "mmc" ]]; then
  die "Loader disk is not USB or SATA/SCSI/NVME/eMMC DoM"
fi

# Save variables to user config file
writeConfigKey "vid" ${VID} "${USER_CONFIG_FILE}"
writeConfigKey "pid" ${PID} "${USER_CONFIG_FILE}"

# Inform user
echo -e "Loader Disk: \033[1;34m${LOADER_DISK}\033[0m"
echo -e "Loader Disk Type: \033[1;34m${BUS^^}\033[0m"

# Load keymap name
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"

# Loads a keymap if is valid
if [ -f "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" ]; then
  echo -e "Loading Keymap: \033[1;34m${LAYOUT}/${KEYMAP}\033[0m"
  zcat "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" | loadkeys
fi
echo

# Grep Config Values
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"

# Decide if boot automatically
if grep -q "force_arc" /proc/cmdline; then
  echo -e "\033[1;34mUser requested edit settings.\033[0m"
elif [ "${BUILDDONE}" = "true" ]; then
  echo -e "\033[1;34mLoader is configured!\033[0m"
  boot.sh && exit 0
else
  echo -e "\033[1;34mUser requested edit settings.\033[0m"
fi
echo

BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
[ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=20
echo -e "\033[1;34mDetected ${N} NIC.\033[0m \033[1;37mWaiting for Connection:\033[0m"
for ETH in ${ETHX}; do
  IP=""
  STATICIP="$(readConfigKey "static.${ETH}" "${USER_CONFIG_FILE}")"
  DRIVER=$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
  COUNT=0
  while true; do
    ARCIP="$(readConfigKey "ip.${ETH}" "${USER_CONFIG_FILE}")"
    if [[ "${STATICIP}" = "true" && -n "${ARCIP}" ]]; then
      NETMASK="$(readConfigKey "netmask.${ETH}" "${USER_CONFIG_FILE}")"
      IP="${ARCIP}"
      NETMASK=$(convert_netmask "${NETMASK}")
      [ ! -n "${NETMASK}" ] && NETMASK="16"
      ip addr add ${IP}/${NETMASK} dev ${ETH}
      MSG="STATIC"
    else
      IP="$(getIP ${ETH})"
      writeConfigKey "static.${ETH}" "false" "${USER_CONFIG_FILE}"
      MSG="DHCP"
    fi
    if [ -n "${IP}" ]; then
      SPEED=$(ethtool ${ETH} | grep "Speed:" | awk '{print $2}')
      writeConfigKey "ip.${ETH}" "${IP}" "${USER_CONFIG_FILE}"
      echo -e "\r\033[1;37m${DRIVER} (${SPEED} | ${MSG}):\033[0m Access \033[1;34mhttp://${IP}:7681\033[0m to connect to Arc via web."
      ethtool -s ${ETH} wol g 2>/dev/null
      break
    fi
    if [ ${COUNT} -gt ${BOOTIPWAIT} ]; then
      echo -e echo -e "\r\033[1;37m${DRIVER}:\033[0m TIMEOUT"
      deleteConfigKey "ip.${ETH}" "${USER_CONFIG_FILE}"
      break
    fi
    sleep 3
    if ethtool ${ETH} | grep 'Link detected' | grep -q 'no'; then
      echo -e "\r\033[1;37m${DRIVER}:\033[0m NOT CONNECTED"
      deleteConfigKey "ip.${ETH}" "${USER_CONFIG_FILE}"
      break
    fi
    COUNT=$((${COUNT} + 3))
  done
done

# Inform user
echo
echo -e "Call \033[1;34marc.sh\033[0m to configure Arc"
echo
echo -e "User config is on \033[1;34m${USER_CONFIG_FILE}\033[0m"
echo -e "Default SSH Root password is \033[1;34marc\033[0m"
echo

mkdir -p "${ADDONS_PATH}"
mkdir -p "${LKM_PATH}"
mkdir -p "${MODULES_PATH}"
mkdir -p "${MODEL_CONFIG_PATH}"
mkdir -p "${PATCH_PATH}"
mkdir -p "${BACKUPDIR}"

# Load Arc
updateAddons
echo -e "\033[1;34mLoading Arc Overlay...\033[0m"
sleep 2

# Diskcheck
HASATA=0
for D in $(lsblk -dpno NAME); do
  [ "${D}" = "${LOADER_DISK}" ] && continue
  if [[ "$(getBus "${D}")" = "sata" || "$(getBus "${D}")" = "scsi" ]]; then
    HASATA=1
    break
  fi
done

# Check memory and load Arc
RAM=$(free -m | grep -i mem | awk '{print$2}')
if [ ${RAM} -le 3500 ]; then
  echo -e "\033[1;31mYou have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of RAM.\033[0m\n"
  echo -e "\033[1;31mUse arc.sh to proceed. Not recommended!\033[0m\n"
elif [ ${HASATA} = "0" ]; then
  echo -e "\033[1;31m*** Please insert at least one Sata/SAS Disk for System Installation, except for the Bootloader Disk. ***\033[0m\n"
  echo -e "\033[1;31mUse arc.sh to proceed. Not recommended!\033[0m\n"
else
  arc.sh
fi