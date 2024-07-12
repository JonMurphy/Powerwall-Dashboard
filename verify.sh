#!/bin/bash
#
# Setup Verification Tool for Powerwall Dashboard

# Stop on Errors
set -e

# Formatting
default="\033[39m"
white="\033[97m"
green="\033[32m"
red="\033[91m"
yellow="\033[33m"
bold="\033[0m${white}\033[1m"
subbold="\033[0m${green}"
normal="${white}\033[0m"
dim="\033[0m${white}\033[2m"
alert="\033[0m${red}\033[1m"
alertdim="\033[0m${red}\033[2m"

# Check for no-color mode
if [ $# -ne 0 ]; then
    # no color
    bold=""
    subbold=""
    normal=""
    dim=""
    alert=""
    alertdim=""
fi

# Set Globals
UKN="${alertdim}Unknown${normal}"
GOOD="${subbold}GOOD${normal}"
CURRENT=$UKN
ALLGOOD=1
if [ -f VERSION ]; then
    CURRENT=`cat VERSION`
fi
TZ=`cat tz`

# Windows Git Bash docker exec compatibility fix
if type winpty > /dev/null 2>&1; then
    shopt -s expand_aliases
    alias docker="winpty -Xallow-non-tty -Xplain docker"
fi

# Service Running Helper Function
running() {
    local url=${1:-http://localhost:80}
    local code=${2:-200}
    if [[ $3 == 1 ]]; then
        head="--head"
    else
        head=""
    fi
    local status=$(curl ${head} -k --location --connect-timeout 5 --write-out %{http_code} --silent --output /dev/null ${url})
    [[ $status == ${code} ]]
}

# Operating system details
case "$OSTYPE" in
    linux*)     OS="Linux" ;;
    darwin*)    OS="MacOS" ;;
    cygwin*)    OS="Windows" ;;
    msys*)      OS="Windows" ;;
    *)          OS="$OSTYPE" ;;
esac

echo -e "${bold}Verify Powerwall-Dashboard ${subbold}${CURRENT}${normal} on ${OS} - Timezone: ${subbold}${TZ}${dim}"
echo -e "----------------------------------------------------------------------------"
echo -e "This script will attempt to verify all the services needed to run"
echo -e "Powerwall-Dashboard. Use this output when you open an issue for help:"
echo -e "https://github.com/jasonacox/Powerwall-Dashboard/issues/new"
echo -e ""

# Check compose env file
COMPOSE_ENV_FILE="compose.env"
if [ ! -f ${COMPOSE_ENV_FILE} ]; then
    echo -e " - ${alert}ERROR: You are missing ${COMPOSE_ENV_FILE}${normal}"
    ALLGOOD=0
fi
echo -e ""

# pypowerwall
echo -e "${bold}Checking pypowerwall${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="pypowerwall"
VER=$UKN
PWVER=$UKN
PWSTATE="${alert}ERROR: Not Connected${dim}"
ENV_FILE="pypowerwall.env"
AUTH_FILE=".auth/.pypowerwall.auth"
PORT="8675"
echo -e -n "${dim} - Config File ${ENV_FILE}: "
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/stats 200 0 2>/dev/null; then
        echo -e $GOOD
        VER=`curl --silent http://localhost:$PORT/stats | awk '{print $2" "$3" "$4}' | cut -d\" -f 2 2>/dev/null`
        SITENAME=`curl --silent http://localhost:$PORT/stats | grep "site_name" | sed 's/.*"site_name": "\(.*\)",.*/\1/' 2>/dev/null`
        CLOUDMODE=`curl --silent http://localhost:$PORT/stats | sed 's/.*"cloudmode": \(.*\), "siteid".*/\1/' 2>/dev/null`
        SITEID=`curl --silent http://localhost:$PORT/stats | sed 's/.*"siteid": \(.*\), "counter".*/\1/' 2>/dev/null`
        # check connection with powerwall
        if running http://localhost:$PORT/version 200 0 2>/dev/null; then
            PWSTATE="CONNECTED"
            PWVER=`curl --silent http://localhost:$PORT/version | awk '{print $2}' | cut -d\" -f 2 2>/dev/null`
        fi
    else
        echo -e "${alert}ERROR: Not Listening${normal}"
        LISTENING="false"
        ALLGOOD=0
    fi
elif [ "$RUNNING" = "false" ]; then
    echo -e "${alert}ERROR: Stopped${normal}"
    ALLGOOD=0
else
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e "${dim} - Powerwall State: ${subbold}$PWSTATE${dim} - Firmware Version: ${subbold}$PWVER${normal}"
if [ -n "$SITENAME" ]; then
    SITEID="$SITEID ($SITENAME)"
fi
if running https://192.168.91.1/tedapi/din 403 0 2>/dev/null; then
    echo -e "${dim} - Powerwall Gateway TEDAPI: ${subbold}Available (192.168.91.1)${dim}"
else
    echo -e "${dim} - Powerwall Gateway TEDAPI: ${normal}Not Available (192.168.91.1)${normal}"
fi
if [ "$CLOUDMODE" = "true" ]; then
    echo -e "${dim} - Cloud Mode: ${subbold}YES ${dim}- Site ID: ${subbold}$SITEID"
elif [ "$LISTENING" = "false" ] && [ -f ${ENV_FILE} ] && ! grep -qE "^PW_HOST=.+" "${ENV_FILE}"; then
    echo -e "${dim} - Cloud Mode: ${subbold}YES ${dim}- ${alert}ERROR: Not Connected to Tesla Cloud${normal}"
    if [ ! -f "${AUTH_FILE}" ]; then
        echo -e "${dim} - Auth File ${AUTH_FILE}: ${alert}ERROR: Missing${normal}"
    fi
    ALLGOOD=0
else
    echo -e "${dim} - Cloud Mode: ${normal}NO"
fi
# Check to see that TZ is set in pypowerwall
if [ -f ${ENV_FILE} ] && ! grep -q "TZ=" ${ENV_FILE}; then
    echo -e "${dim} - ${alertdim}ERROR: Your pypowerwall settings are missing TZ.${normal}"
    ALLGOOD=0
fi
echo -e ""

# telegraf
echo -e "${bold}Checking telegraf${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="telegraf"
VER=$UKN
PORT=""
CONF_FILE="telegraf.conf"
echo -e -n "${dim} - Config File ${CONF_FILE}: "
if [ ! -f ${CONF_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
CONF_FILE="telegraf.local"
echo -e -n "${dim} - Local Config File ${CONF_FILE}: "
if [ ! -f ${CONF_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    VER=`v=$(docker exec --tty $CONTAINER sh -c "telegraf --version") && echo "$v" || echo "$UKN"`
elif [ "$RUNNING" = "false" ]; then
    echo -e "${alert}ERROR: Stopped${normal}"
    ALLGOOD=0
else
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

# influxdb
echo -e "${bold}Checking influxdb${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="influxdb"
VER=$UKN
CONF_FILE="influxdb.conf"
ENV_FILE="influxdb.env"
PORT="8086"
echo -e -n "${dim} - Config File ${CONF_FILE}: "
if [ ! -f ${CONF_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Environment File ${ENV_FILE}: "
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/ping 204 1 2>/dev/null; then
        echo -e $GOOD
        VER=`v=$(docker exec --tty $CONTAINER sh -c "influx -version") && echo "$v" || echo "$UKN"`
    else
        echo -e "${alert}ERROR: Not Listening${normal}"
        ALLGOOD=0
    fi
    echo -e -n "${dim} - Filesystem (./$CONTAINER): "
    rm -f ./influxdb/WRITE
    ERR=`docker exec -it $CONTAINER sh -c "touch /var/lib/influxdb/WRITE 2>/dev/null"` || true
    if [ -e "./influxdb/WRITE" ]; then
        echo -e $GOOD
        rm -f ./influxdb/WRITE
    else
        echo -e "${alert}ERROR: Unable to write to filesystem - check permissions${normal}"
        ALLGOOD=0
    fi
elif [ "$RUNNING" = "false" ]; then
    echo -e "${alert}ERROR: Stopped${normal}"
    ALLGOOD=0
else
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

# grafana
echo -e "${bold}Checking grafana${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="grafana"
VER=$UKN
PORT="9000"
ENV_FILE="grafana.env"
echo -e -n "${dim} - Config File ${ENV_FILE}: "
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
    if ! grep -q "yesoreyeram-boomtable-panel-1.5.0-alpha.3.zip" $ENV_FILE; then
        echo -e "${dim} - ${alertdim}WARNING: Your Grafana settings are outdated."
    fi
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    VER=`v=$(docker exec --tty $CONTAINER sh -c "grafana-cli --version") && echo "$v" || echo "$UKN"`
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/login 200 1 2>/dev/null; then
        echo -e $GOOD
    else
        echo -e "${alert}ERROR: Not Listening - Logs:${alertdim}"
        echo -e "---"
        docker logs $CONTAINER 2>&1 | tail -11
        echo -e "---${normal}"
        ALLGOOD=0
    fi
    echo -e -n "${dim} - Filesystem (./$CONTAINER): "
    rm -f ./grafana/WRITE
    ERR=`docker exec -it $CONTAINER sh -c "touch /var/lib/grafana/WRITE 2>/dev/null"` || true
    if [ -e "./grafana/WRITE" ]; then
        echo -e $GOOD
        rm -f ./grafana/WRITE
    else
        echo -e "${alert}ERROR: Unable to write to filesystem - check permissions${normal}"
        ALLGOOD=0
    fi
elif [ "$RUNNING" = "false" ]; then
    echo -e "${alert}ERROR: Stopped${normal}"
    ALLGOOD=0
else
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

if grep -q "tesla-history" powerwall.extend.yml 2>/dev/null; then
    # tesla-history
    echo -e "${bold}Checking tesla-history${dim}"
    echo -e "----------------------------------------------------------------------------"
    CONTAINER="tesla-history"
    VER=$UKN
    CONF_FILE="tools/tesla-history/tesla-history.conf"
    AUTH_FILE="tools/tesla-history/tesla-history.auth"
    echo -e -n "${dim} - Config File ${CONF_FILE}: "
    if [ ! -f ${CONF_FILE} ]; then
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    else
        echo -e $GOOD
    fi
    echo -e -n "${dim} - Auth File ${AUTH_FILE}: "
    if [ ! -f ${AUTH_FILE} ]; then
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    else
        echo -e $GOOD
    fi
    echo -e -n "${dim} - Container ($CONTAINER): "
    RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
    if [ "$RUNNING" = "true" ]; then
        echo -e $GOOD
        VER=`v=$(docker exec -it $CONTAINER sh -c "python3 tesla-history.py --version") && echo "$v" || echo "$UKN"`
    elif [ "$RUNNING" = "false" ]; then
        echo -e "${alert}ERROR: Stopped${normal}"
        ALLGOOD=0
    else
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    fi
    echo -e "${dim} - Version: ${subbold}$VER"
    echo -e ""
fi

# weather411
echo -e "${bold}Checking weather411${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="weather411"
VER=$UKN
WEATHER=$UKN
ENV_FILE="weather/weather411.conf"
PORT="8676"
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${dim} - Skipped: weather411 not set up (missing ${ENV_FILE})"
else
    echo -e -n "${dim} - Container ($CONTAINER): "
    RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
    if [ "$RUNNING" = "true" ]; then
        echo -e $GOOD
        echo -e -n "${dim} - Service (port $PORT): "
        if running http://localhost:$PORT/stats 200 0 2>/dev/null; then
            echo -e $GOOD
            VER=`curl --silent http://localhost:$PORT/stats | awk '{print $2" "$3" "$4}' | cut -d\" -f 2 2>/dev/null`
            # check connection with openweather
            if running http://localhost:$PORT/temp 200 0 2>/dev/null; then
                WEATHER=`curl --silent http://localhost:$PORT/temp 2>/dev/null`
            fi
            echo -e "${dim} - Weather: ${subbold}${WEATHER}"
        else
            echo -e "${alert}ERROR: Not Listening - Logs:${alertdim}"
            echo -e "---"
            docker logs $CONTAINER 2>&1 | tail -11
            echo -e "---${normal}"
            ALLGOOD=0
        fi
    elif [ "$RUNNING" = "false" ]; then
        echo -e "${alert}ERROR: Stopped${normal}"
        ALLGOOD=0
    else
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    fi
    echo -e "${dim} - Version: ${subbold}$VER"
fi
echo -e ""

if grep -q "ecowitt" powerwall.extend.yml 2>/dev/null; then
    # ecowitt
    echo -e "${bold}Checking ecowitt${dim} (optional component - OK if missing)"
    echo -e "----------------------------------------------------------------------------"
    CONTAINER="ecowitt"
    VER=$UKN
    WEATHER=$UKN
    ENV_FILE="weather/contrib/ecowitt/ecowitt.conf"
    PORT="8686"
    echo -e -n "${dim} - Config File ${ENV_FILE}: "
    if [ ! -f ${ENV_FILE} ]; then
        echo -e "${alertdim}Missing - ecowitt not set up"
        ALLGOOD=0
    else
        echo -e $GOOD
    fi
    echo -e -n "${dim} - Container ($CONTAINER): "
    RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
    if [ "$RUNNING" = "true" ]; then
        echo -e $GOOD
        echo -e -n "${dim} - Service (port $PORT): "
        if running http://localhost:$PORT/stats 200 0 2>/dev/null; then
            echo -e $GOOD
            VER=`curl --silent http://localhost:$PORT/stats | awk '{print $2" "$3" "$4}' | cut -d\" -f 2 2>/dev/null`
            # check connection with ecowitt
            if running http://localhost:$PORT/temp 200 0 2>/dev/null; then
                WEATHER=`curl --silent http://localhost:$PORT/temp 2>/dev/null`
            fi
            echo -e "${dim} - Weather: ${subbold}${WEATHER}"
        else
            echo -e "${alert}ERROR: Not Listening - Logs:${alertdim}"
            echo -e "---"
            docker logs $CONTAINER 2>&1 | tail -11
            echo -e "---${normal}"
            ALLGOOD=0
        fi
    elif [ "$RUNNING" = "false" ]; then
        echo -e "${alert}ERROR: Stopped${normal}"
        ALLGOOD=0
    else
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    fi
    echo -e "${dim} - Version: ${subbold}$VER"
    echo -e ""
fi

if [ $ALLGOOD -ne 1 ]; then
    echo -e "${alert}One or more tests failed.${normal}"
    exit 1
else
    echo -e "${subbold}All tests succeeded.${normal}"
    exit 0
fi
