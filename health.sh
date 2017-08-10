#!/bin/bash

#
# Script By Anton Zheltyshev
# Version 1.0.5
# Contacts info@maxrival.com
#
# Github Storj Project - https://github.com/Storj/storjshare-daemon
# Github Storj-Utils - https://github.com/AntonMZ/Storj-Utils
#

#change these variables according to your environment
LOGS_FOLDER='$HOME/.config/storjshare/logs'
WATCHDOG_LOG='$LOGS_FOLDER/daemon.log'

# Prechecks
#------------------------------------------------------------------------------
SHELL=$(echo $SHELL | grep bash)
if [[ -z $SHELL ]]; then
  echo 'Please use only bash'
  exit 0
fi

# check if jq is installed
if ! hash jq 2>/dev/null; then
  echo "Please install jq first, more info about jq @ https://stedolan.github.io/jq/"
  exit 0
fi

# check nvm env & storjshare
if ! hash storjshare 2>/dev/null; then
  echo "Please install storjshare or enable nvm env"
  exit 0
fi

#check netstat for linux-*
if [[ "$OSTYPE" == "linux-"* ]]; then
  if ! hash netstat 2>/dev/null; then
    echo "Please install net-tools packet"
    exit 0
  fi
fi

function help()
{
    echo -e " \n" \
    "Version 1.0.5\n" \
    "\n" \
    "Github Storj Project - https://github.com/Storj/storjshare-daemon\n" \
    "Github Storj-Utils - https://github.com/AntonMZ/Storj-Utils\n" \
    "Usage: healt.sh [options]\n\n" \
    "Options:\n" \
    "--cli - enable cli mode (ex: sh health.sh --cli)\n" \
    "--api - enable api mode (ex: sh health.sh --api)\n\n" 
}

if [[ "$1" != "--cli" ]] && [[ "$1" != "--api" ]]; then
  help
  exit 0
fi

# Variables
#------------------------------------------------------------------------------
VER='1.0.5'
HOSTNAME=$(hostname)
YEAR=$(date +%Y)
MONTH=$(date +%-m)
DAY=$(date +%-d)
DATE=$(date)
UPTIME=$(date +%s)

if [[ "$OSTYPE" == "linux-"* ]]; then
	IP=$(hostname -I)
	SESSIONS=$(netstat -np | grep node | grep -c tcp)
elif [[ "$OSTYPE" == "freebsd"* ]]; then
	IP=$(ifconfig | grep "inet " | grep -v "inet6"  | grep -v "127.0.0.1" | awk '{print $2}' | tr '\n' ' ')
	SS_PID=$(pgrep -f "farmer")
	SESSIONS=$(sockstat -c | grep -v "stream" | grep -c " $SS_PID " | awk '{print $1}')
else
	IP="n/a for $OSTYPE"
	SESSIONS="n/a for $OSTYPE"
fi

WATCHDOG_LOG_DATE=$(date +%x)
STORJ=$(storjshare -V)
RTMAX='1000'
ERR2='Big time response'
ERR3='Is not null'

if [[ "$1" == --cli ]]; then
	printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
fi

if [[ "$1" == --cli ]]; then
	echo -e " Version script:^ \e[0;32m $VER \e[0m \n" \
	"Hostname:^ \e[0;32m $HOSTNAME \e[0m \n" \
	"Ip:^ \e[0;32m $IP \e[0m \n" \
	"Date:^ \e[0;32m $DATE \e[0m \n" \
	"Open Sessions:^ \e[0;32m $SESSIONS \e[0m \n" \
	"Storjshare Version:^ \e[0;32m $STORJ \e[0m" | column -t -s '^'
fi

DATA=$(storjshare status | grep running | awk -F ' ' '{print $2}')

if [[ -n "$DATA" ]]; then
	if [[ "$1" == --cli ]]; then
		printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
	fi

	for line in $DATA; do
		CURL=$(curl -s https://api.storj.io/contacts/"$line")
		ADDRESS=$(echo "$CURL" | jq -r '.address')
		if [[ "$ADDRESS" == null ]]; then
			ADDRESS=$(echo -e "\e[0;31mAPI Server does not contain a parameter\e[0m")
		fi

		LS=$(echo "$CURL" | jq -r '.lastSeen')
		if [[ "$LS" == null ]]; then
			LS=$(echo -e "\e[0;31mAPI Server does not contain a parameter\e[0m")
		fi

		RT=$(echo "$CURL" | jq '.responseTime' | awk -F '.' '{print $1}')
		if [[ "$RT" == null ]]; then
			RT=$(echo 0)
		fi

		AGENT=$(echo "$CURL" | jq -r '.userAgent')
		if [[ "$AGENT" == null ]]; then
			AGENT=$(echo "API Server does not contain a parameter\e[0m")
		fi

		PORT=$(echo "$CURL" | jq -r '.port')
		if [[ "$PORT" == null ]]; then
			PORT=$(echo -e "\e[0;31mAPI Server does not contain a parameter\e[0m")
		fi

		PROTOCOL=$(echo "$CURL" | jq -r '.protocol')
		if [[ "$PROTOCOL" == null ]]; then
			PROTOCOL=$(echo -e "\e[0;31mAPI Server does not contain a parameter\e[0m")
		fi
		
		LT=$(echo "$CURL" | jq -r '.lastTimeout')
		if [[ "$LT" == null ]]; then
			LT=$(echo -e "\e[0;31mAPI Server does not contain a parameter\e[0m")
		fi
		
		TR=$(echo "$CURL" | jq -r '.timeoutRate')
		if [[ "$TR" == null ]]; then
			TR=$(echo "err")
		fi

		PORT_STATUS=$(curl --silent -k "https://storjstat.com:3000/portstatus?hostname=$ADDRESS&port=$PORT" | jq -r '.status')
		LOG_FILE="$LOGS_FOLDER"/"$line""_""$YEAR-$MONTH-$DAY".log
		#LOG_FILE="$LOGS_FOLDER"/"$line""_""$YEAR-$MONTH-$DAY".log
		DELTA=$(grep -R 'delta' "$LOG_FILE" | tail -1 | awk -F ',' '{print $3}' | awk -F ' ' '{print $2}')

		# Watchdog restart couns
		if [[ ! -f "$WATCHDOG_LOG" ]]; then
			RESTART_NODE_COUNT=$(echo -e "\e[0;32mNo log file\e[0m")
		else
			RESTART_NODE_COUNT=$(grep "$WATCHDOG_LOG_DATE" "$WATCHDOG_LOG" | grep 'RESTARTED' | grep -c "$line")
				if [[ "$RESTART_NODE_COUNT" = 0 ]]; then
					RESTART_NODE_COUNT=$(echo -e "\e[0;32m0\e[0m")
				else
					RESTART_NODE_COUNT=$(echo -e "\e[0;31m$RESTART_NODE_COUNT\e[0m")
				fi
		fi

		#--------------------------------------------------------------------------------------------
		# Share allocated
		SHARE_ALLOCATED_TMP=$(cat < "$LOG_FILE" | grep storageAllocated | tail -1 | awk -F ':' '{print $6}' | awk -F ',' '{print $1}')
		let SHARE_ALLOCATED=$SHARE_ALLOCATED_TMP/1024/1024/1024

		#--------------------------------------------------------------------------------------------
		# Share_used
		SHARE_USED_TMP=$(cat < "$LOG_FILE" | grep storageUsed | tail -1 | awk -F ':' '{print $7}' | awk -F ',' '{print $1}')
		let SHARE_USED=$SHARE_USED_TMP/1024/1024/1024

		#--------------------------------------------------------------------------------------------
		# Last publish
		LAST_PUBLISH=$(grep -R 'PUBLISH' "$LOG_FILE" | tail -1 | awk -F ',' '{print $NF}' | cut -b 14-37)
		if [[ -z "$LAST_PUBLISH" ]]; then
			LAST_PUBLISH=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		# Publish counts
		PUBLISH_COUNT=$(grep -cR 'PUBLISH' "$LOG_FILE")
		if [[ -z "$PUBLISH_COUNT" ]]; then
			PUBLISH_COUNT=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		# Last offer
		LAST_OFFER=$(grep -R 'OFFER' "$LOG_FILE" | tail -1 | awk -F ',' '{print $NF}' | cut -b 14-37)
		if [[ -z "$LAST_OFFER" ]]; then
			LAST_OFFER=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		# Offers counts
		OFFER_COUNT=$(grep -cR 'OFFER' "$LOG_FILE")
		if [[ -z "$OFFER_COUNT" ]]; then
			OFFER_COUNT=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		# Last consigned
		LAST_CONSIGNMENT=$(grep -R 'consignment' "$LOG_FILE" | tail -1 | awk -F ',' '{print $NF}' | cut -b 14-37)
		if [[ -z "$LAST_CONSIGNMENT" ]]; then
			LAST_CONSIGNMENT=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		# Consigned counts
		CONSIGNMENT_COUNT=$(grep -cR 'consignment' "$LOG_FILE")
		if [[ -z "$CONSIGNMENT_COUNT" ]]; then
			CONSIGNMENT_COUNT=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		# Last download
		LAST_DOWNLOAD=$(grep -R 'download' "$LOG_FILE" | tail -1 | awk -F ',' '{print $NF}' | cut -b 14-37)
		if [[ -z "$LAST_DOWNLOAD" ]]; then
			LAST_DOWNLOAD=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		# Download counts
		DOWNLOAD_COUNT=$(grep -cR 'download' "$LOG_FILE")
		if [[ -z "$DOWNLOAD_COUNT" ]]; then
			DOWNLOAD_COUNT=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		# Last upload
		LAST_UPLOAD=$(grep -R 'upload' "$LOG_FILE" | tail -1 | awk -F ',' '{print $NF}' | cut -b 14-37)
		if [[ -z "$LAST_UPLOAD" ]]; then
			LAST_UPLOAD=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		# Upload counts
		UPLOAD_COUNT=$(grep -cR 'upload' "$LOG_FILE")
		if [[ -z "$UPLOAD_COUNT" ]]; then
			UPLOAD_COUNT=$(echo '-')
		fi

		#--------------------------------------------------------------------------------------------
		if [[ "$TR" == 0 ]]; then
			TR_STATUS=$(echo -e "\e[0;32mgood\e[0m")
		elif [[ "$TR" == err ]]; then
			TR_STATUS=$(echo -e "\e[0;31mAPI Server does not contain a parameter\e[0m")
		else
			TR_STATUS=$(echo -e "\e[0;31mbad / $ERR3 \e[0m")
		fi


		if [[ "$PORT_STATUS" == "open" ]]; then
			PORT_STATUS=$(echo -e "\e[0;32mopen\e[0m")
		elif [[ "$PORT_STATUS" == "closed" ]]; then
			PORT_STATUS=$(echo -e "\e[0;31mclosed\e[0m")
		elif [[ "$PORT_STATUS" == "filtered" ]]; then
			PORT_STATUS=$(echo -e "\e[0;33mfiltered\e[0m")
		elif [[ "$PORT_STATUS" == "wrong parametrs" ]]; then
			PORT_STATUS=$(echo -e "\e[0;31mwrong parametrs\e[0m")
		else
			PORT_STATUS=$(echo -e "\e[0;33mapi / Server not available \e[0m")
		fi

		if [[ -z "$DELTA" ]]; then
			DELTA=$(echo -e "\e[0;35mNone /\e[0m")
			DELTASTATUS=$(echo -e "\e[0;35mMaybe you need enable mode 3 in config file! or delta not present in log file /need restart nodes/\e[0m")
		else
			if [[ "$DELTA" -ge '500' ]] || [[ "$DELTA" -le '-500' ]]; then
				DELTASTATUS=$(echo -e "/ \e[0;31mbad / Your clock is not synced with a time server\e[0m")
			elif [[ "$DELTA" -ge '50' ]] || [[ "$DELTA" -le '-50' ]]; then
				DELTASTATUS=$(echo -e "/ \e[0;33mmedium / Your clock is not synced with a time server\e[0m")
			else
				DELTASTATUS=$(echo -e "/ \e[0;32mgood / Your clock is synced with a time server \e[0m")
			fi
		fi

		if [[ "$RT" -ge "$RTMAX" ]]; then
			RT=$(echo -e "$RT /\e[0;31m bad / $ERR2\e[0m")
		else
			RT=$(echo -e "$RT / \e[0;32mgood\e[0m")
		fi

		if [[ "$1" == --cli ]]; then
		{
			echo -e " NodeID:^ $line \n" \
			"Restarts Node:^ $RESTART_NODE_COUNT \n" \
			"Log_file:^ "$LOG_FILE" \n" \
			"ResponseTime:^ $RT \n" \
			"Address:^ $ADDRESS \n" \
			"User Agent:^ $AGENT \n" \
			"Last Seen:^ $LS \n" \
			"Port:^ $PORT / $PORT_STATUS \n" \
			"Protocol:^ $PROTOCOL \n" \
			"Last Timeout:^ $LT \n" \
			"Timeout Rate:^ $TR / $TR_STATUS \n" \
			"DeltaTime:^ $DELTA $DELTASTATUS \n" \
			"Share_allocated:^ $SHARE_ALLOCATED GB (telemetry report)\n" \
			"Share_Used:^ $SHARE_USED GB (telemetry report)\n" \
			"Last publish:^ $LAST_PUBLISH \n" \
			"Last offer:^ $LAST_OFFER \n" \
			"Last consigned:^ $LAST_CONSIGNMENT \n" \
			"Last download:^ $LAST_DOWNLOAD \n" \
			"Last upload:^ $LAST_UPLOAD \n" \
			"Offers counts:^ $OFFER_COUNT \n" \
			"Publish counts:^ $PUBLISH_COUNT \n" \
			"Download counts:^ $DOWNLOAD_COUNT \n" \
			"Upload counts:^ $UPLOAD_COUNT \n" \
			"Consignment counts:^ $CONSIGNMENT_COUNT \n" | column -t -s '^'

			printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
		}
		fi

		if [[ "$1" == --api ]]; then
		{
			curl -X POST \
			-F "node_id=$line" \
			-F "address=$ADDRESS" \
			-F "uptime=$UPTIME" \
			-F "agent=$AGENT" \
			-F "port=$PORT" \
			-F "rt=$RT" \
			-F "port_status=$PORT_STATUS" \
			-F "share_allocated=$SHARE_ALLOCATED" \
			-F "ls=$LS" \
			-F "protocol=$PROTOCOL" \
			-F "lt=$LT" \
			-F "tr=$TR" \
			-F "tr_status=$TR_STATUS" \
			-F "delta=$DELTA" \
			-F "share_used=$SHARE_USED" \
			-F "last_publish=$LAST_PUBLISH" \
			-F "last_offer=$LAST_OFFER" \
			-F "last_consignment=$LAST_CONSIGNMENT" \
			-F "last_download=$LAST_DOWNLOAD" \
			-F "last_upload=$LAST_UPLOAD" \
			-F "offer_count=$OFFER_COUNT" \
			-F "publish_count=$PUBLISH_COUNT" \
			-F "download_count=$DOWNLOAD_COUNT" \
			-F "upload_count=$UPLOAD_COUNT" \
			-F "consignment_count=$CONSIGNMENT_COUNT" \
			-F "restart_count=$RESTART_NODE_COUNT" https://api.storj.maxrival.com
		}
		fi
	done
fi


