#!/bin/bash
VPN_PROVIDER="${OPENVPN_PROVIDER,,}"
VPN_PROVIDER_CONFIGS="/etc/openvpn/${VPN_PROVIDER}"

# If create_tun_device is set, create /dev/net/tun
if [[ "${CREATE_TUN_DEVICE,,}" == "true" ]]; then
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200
  chmod 0666 /dev/net/tun
fi

if [[ "${OPENVPN_PROVIDER}" == "**None**" ]] || [[ -z "${OPENVPN_PROVIDER-}" ]]; then
  echo "OpenVPN provider not set. Exiting."
  exit 1
elif [[ ! -d "${VPN_PROVIDER_CONFIGS}" ]]; then
  echo "Could not find OpenVPN provider: ${OPENVPN_PROVIDER}"
  echo "Please check your settings."
  exit 1
fi

echo "Using OpenVPN provider: ${OPENVPN_PROVIDER}"

# If openvpn-pre-start.sh exists, run it
if [ -x /scripts/openvpn-pre-start.sh ]
then
   echo "Executing /scripts/openvpn-pre-start.sh"
   /scripts/openvpn-pre-start.sh "$@"
   echo "/scripts/openvpn-pre-start.sh returned $?"
fi

if [[ "${OPENVPN_PROVIDER^^}" = "NORDVPN" ]]
then
    if [[ -z $NORDVPN_PROTOCOL ]]
    then
      export NORDVPN_PROTOCOL=UDP
    fi

    if [[ -z $NORDVPN_CATEGORY ]]
    then
      export NORDVPN_CATEGORY=P2P
    fi

    if [[ ! -z $OPENVPN_CONFIG ]]
    then
      tmp_Protocol="${OPENVPN_CONFIG##*.}"
      export NORDVPN_PROTOCOL=${tmp_Protocol^^}
      echo "Setting NORDVPN_PROTOCOL to: ${NORDVPN_PROTOCOL}"
      ${VPN_PROVIDER_CONFIGS}/updateConfigs.sh --openvpn-config
    elif [[ ! -z $NORDVPN_COUNTRY ]]
    then
      export OPENVPN_CONFIG=$(${VPN_PROVIDER_CONFIGS}/updateConfigs.sh)
    else
      export OPENVPN_CONFIG=$(${VPN_PROVIDER_CONFIGS}/updateConfigs.sh --get-recommended})
    fi
elif [[ "${OPENVPN_PROVIDER^^}" = "FREEVPN" ]]
then
    FREEVPN_DOMAIN=${OPENVPN_CONFIG%%-*}
    export OPENVPN_PASSWORD=$(curl -s https://freevpn.${FREEVPN_DOMAIN:-"be"}/accounts/ | grep Password |  sed s/"^.*Password\:.... "/""/g | sed s/"<.*"/""/g)
fi

if [[ -n "${OPENVPN_CONFIG-}" ]]; then
  readarray -t OPENVPN_CONFIG_ARRAY <<< "${OPENVPN_CONFIG//,/$'\n'}"
  ## Trim leading and trailing spaces from all entries. Inefficient as all heck, but works like a champ.
  for i in "${!OPENVPN_CONFIG_ARRAY[@]}"; do
    OPENVPN_CONFIG_ARRAY[${i}]="${OPENVPN_CONFIG_ARRAY[${i}]#"${OPENVPN_CONFIG_ARRAY[${i}]%%[![:space:]]*}"}"
    OPENVPN_CONFIG_ARRAY[${i}]="${OPENVPN_CONFIG_ARRAY[${i}]%"${OPENVPN_CONFIG_ARRAY[${i}]##*[![:space:]]}"}"
  done
  if (( ${#OPENVPN_CONFIG_ARRAY[@]} > 1 )); then
    OPENVPN_CONFIG_RANDOM=$((RANDOM%${#OPENVPN_CONFIG_ARRAY[@]}))
    echo "${#OPENVPN_CONFIG_ARRAY[@]} servers found in OPENVPN_CONFIG, ${OPENVPN_CONFIG_ARRAY[${OPENVPN_CONFIG_RANDOM}]} chosen randomly"
    OPENVPN_CONFIG="${OPENVPN_CONFIG_ARRAY[${OPENVPN_CONFIG_RANDOM}]}"
  fi

  if [[ -f "${VPN_PROVIDER_CONFIGS}/${OPENVPN_CONFIG}.ovpn" ]]; then
    echo "Starting OpenVPN using config ${OPENVPN_CONFIG}.ovpn"
    OPENVPN_CONFIG="${VPN_PROVIDER_CONFIGS}/${OPENVPN_CONFIG}.ovpn"
  else
    echo "Supplied config ${OPENVPN_CONFIG}.ovpn could not be found."
    echo "Using default OpenVPN gateway for provider ${VPN_PROVIDER}"
    OPENVPN_CONFIG="${VPN_PROVIDER_CONFIGS}/default.ovpn"
  fi
else
  echo "No VPN configuration provided. Using default."
  OPENVPN_CONFIG="${VPN_PROVIDER_CONFIGS}/default.ovpn"
fi

# add OpenVPN user/pass
if [[ "${OPENVPN_USERNAME}" == "**None**" ]] || [[ "${OPENVPN_PASSWORD}" == "**None**" ]] ; then
  if [[ ! -f /config/openvpn-credentials.txt ]] ; then
    echo "OpenVPN credentials not set. Exiting."
    exit 1
  fi
  echo "Found existing OPENVPN credentials..."
else
  echo "Setting OPENVPN credentials..."
  mkdir -p /config
  echo "${OPENVPN_USERNAME}" > /config/openvpn-credentials.txt
  echo "${OPENVPN_PASSWORD}" >> /config/openvpn-credentials.txt
  chmod 600 /config/openvpn-credentials.txt
fi

## If we use LOCAL_NETWORK we need to grab network config info
if [[ -n "${LOCAL_NETWORK-}" ]]; then
  eval $(/sbin/ip r l | awk '{if ($1 ~ /0.0.0.0|default/ && $5!="tun0") {print "GW="$3"\nINT="$5; exit}}')
fi

if [[ -n "${LOCAL_NETWORK-}" ]]; then
  if [[ -n "${GW-}" ]] && [[ -n "${INT-}" ]]; then
    for localNet in ${LOCAL_NETWORK//,/ }; do
      echo "adding route to local network ${localNet} via ${GW} dev ${INT}"
      /sbin/ip r a "${localNet}" via "${GW}" dev "${INT}"
    done
  fi
fi

exec openvpn ${OPENVPN_OPTS} --config "${OPENVPN_CONFIG}"
