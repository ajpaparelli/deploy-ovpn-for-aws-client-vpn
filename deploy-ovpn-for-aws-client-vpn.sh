#!/bin/bash
#######################################
# Deploy a ovpn file for aws client vpn
# Arguments:
#   $1: OpenVPN file
#       e.g.) file://tmp/aws-vpn.ovpn
#   $2: Profile name displayed in AWS VPN Client
#       e.g.) aws-vpn
#   $3: CvpnEndpointId
#       e.g.) cvpn-endpoint-XXXXXXXXXXXXXXXXX
#   $4: CvpnEndpointRegion
#       e.g.) ap-northeast-1
#   $5: CompatibilityVersion
#       1 : Use mutual authentication
#         : Use Active Directory authentication
#       2 : Use Federated authentication
#   $6: FederatedAuthType
#       0 : Use mutual authentication
#         : Use Active Directory authentication
#       1 : Use Federated authentication
# If you do not know the Arguments, please check the following file path.
# {LOGGED_IN_USER}/.config/AWSVPNClient/ConnectionProfiles
#######################################

# TODO(enpipi) : Checking the behavior when using Active Directory authentication. (enhancement #1)
VERSION='0.2.0'
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
ovpnProfileURL="https://s3.amazonaws.com/cdn.knowthycustomer.com/VPN_Profiles"
awsvpnURL="https://d20adtppz83p9s.cloudfront.net/OSX/latest/AWS_VPN_Client.pkg"
declare -a profiles=("development.ovpn" "LTV-Internal.ovpn") 

dmgfile="AWS_VPN_Client.pkg"
logfile="./Logs/AWSVPNInstallScript.log"

# Output info log with timestamp
print_info_log(){
  local timestamp
  timestamp=$(date +%F\ %T)

  echo "$timestamp [INFO] $1"
}

# Output error log with timestamp
print_error_log(){
  local timestamp
  timestamp=$(date +%F\ %T)

  echo "$timestamp [ERROR] $1"
}

# Find the loggedInUser
LOGGED_IN_USER=$(stat -f %Su /dev/console)

VPN_APP_PATH="/Applications/AWS VPN Client/AWS VPN Client.app"
USER_VPN_APP_PATH="/Users/$LOGGED_IN_USER/Applications/AWS VPN Client/AWS VPN Client.app"

# Check for the existence of aws client vpn
if [[ ! -e ${VPN_APP_PATH} ]];then
  /usr/bin/curl -D- -o /dev/null -s https://d20adtppz83p9s.cloudfront.net/OSX/latest
  if [[ $? != 0 ]]; then
    echo "AWS not Reachable, Check Internet Connection"
    exit $?
  else
    echo "Force Updating AWS VPN"
    /bin/echo "--" >> ${logfile}
    /bin/echo "`date`: Downloading latest version." >> ${logfile}
    /usr/bin/curl -L -o /tmp/${dmgfile} ${awsvpnURL}
    /bin/echo "`date`: Installing..." >> ${logfile}
    /bin/sleep 10
    installer -verbose -pkg /tmp/${dmgfile} -target /Applications >> ${logfile}
    /bin/echo "`date`: Deleting installer." >> ${logfile}
    /bin/rm /tmp/"${dmgfile}"
    /bin/echo "`date`: AWS VPN installed successfully" >> ${logfile}
  fi
fi

if [[ "${1}" = "/" ]];then
	# Jamf uses sends '/' as the first argument
  print_info_log "Shifting arguments for Jamf."
  shift 3
fi

if [[ "${1:l}" = "version" ]];then
  echo "${VERSION}"
  exit 0
fi

print_info_log "Start aws vpn client profile deplyment..."


# Launch and exit the application to generate the initial config file.
# If you don't do this, the application won't launch properly even if you place the ovpn file in the config.
# TODO: Find a way to get the difference when adding and not launch the application.
print_info_log "Opening VPN Client at $VPN_APP_PATH"
open -a "${VPN_APP_PATH}"
osascript -e 'quit app "AWS VPN Client.app"'
sleep 5
# Set the file path to the ConnectionProfiles file with the loggedIn user
CONNECTION_PROFILES="/Users/$LOGGED_IN_USER/.config/AWSVPNClient/ConnectionProfiles"
OPEN_VPN_CONFIGS_DIRECTORY="/Users/$LOGGED_IN_USER/.config/AWSVPNClient/OpenVpnConfigs"
print_info_log "Obtaining VPN Profiles"

for val in ${profiles[@]}
do
  profile_url="$ovpnProfileURL/$val"
  /usr/bin/curl -o /tmp/${val} ${profile_url}
done
i=0
str=""
FILES="/tmp/*.ovpn"
for f in $FILES 
do
    cvpn=$(grep -o -e 'cvpn-endpoint-\w*' $f)
    fname=$(basename $f)
    profile=${fname%.*}
    echo "$cvpn : $fname"
    # Delete auth-federate in OVPN_FILE_PATH
    print_info_log "delete auth-federate in ${f}"
    fed=$(sed -i '' '/auth-federate/d' "${f}")

    #Copy and rename ovpn file
    print_info_log "copy and rename ovpn file from ${f} to ${OPEN_VPN_CONFIGS_DIRECTORY}/${profile}"
    cp "${f}" "${OPEN_VPN_CONFIGS_DIRECTORY}/${profile}"

    if [ $i -gt 0 ]
    then
      str="${str},"
    fi
    let "i+=1"
    str="${str}{ 
      \"ProfileName\":\"${profile}\", 
      \"OvpnConfigFilePath\":\"/Users/$LOGGED_IN_USER/.config/AWSVPNClient/OpenVpnConfigs/${profile}\", 
      \"CvpnEndpointId\":\"$cvpn\", 
      \"CvpnEndpointRegion\":\"us-east-1\", 
      \"CompatibilityVersion\":\"2\", 
      \"FederatedAuthType\":1 
    }"
done

    # Get backup of ConnectionProfiles
print_info_log "Get backup of ${CONNECTION_PROFILES}"
CONNECTION_PROFILES_BACKUP="/Users/$LOGGED_IN_USER/.config/AWSVPNClient/_ConnectionProfiles"
cp "$CONNECTION_PROFILES" "$CONNECTION_PROFILES_BACKUP"


# Make the file
# TODO(enpipi): Add the profile if it already exists, or overwrite it if it doesn't.
# We need to realize this TODO with awk and sed.
# This is because we have to assume that the terminal does not have JQ installed on it.
cat <<EOF > "$CONNECTION_PROFILES"
  {
    "Version":"1",
    "LastSelectedProfileIndex":0,
    "ConnectionProfiles":[
    ${str}
  ]
}
EOF
for val in ${profiles[@]}
do
  /bin/rm /tmp/"${val}"
done
print_info_log "End aws vpn client profile deplyment..."


# Fix permissions
chown "$LOGGED_IN_USER" "$CONNECTION_PROFILES"
