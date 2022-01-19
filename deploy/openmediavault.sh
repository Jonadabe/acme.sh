#!/usr/bin/env sh

########  Public functions #####################

#domain keyfile certfile cafile fullchain
openmediavault_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _getdeployconf DEPLOY_OMV_HOST

  if [ -z "$DEPLOY_OMV_HOST" ]; then
    _debug "Using _cdomain as DEPLOY_OMV_HOST, please set if not correct."
    DEPLOY_OMV_HOST="$_cdomain"
  fi

  _getdeployconf DEPLOY_OMV_WEBUI_ADMIN

  if [ -z "$DEPLOY_OMV_WEBUI_ADMIN" ]; then
    DEPLOY_OMV_WEBUI_ADMIN="admin"
  fi

  _getdeployconf DEPLOY_OMV_SSH_USER

  if [ -z "$DEPLOY_OMV_SSH_USER" ]; then
    DEPLOY_OMV_SSH_USER="root"
  fi

  _savedeployconf DEPLOY_OMV_HOST "$DEPLOY_OMV_HOST"
  _savedeployconf DEPLOY_OMV_WEBUI_ADMIN "$DEPLOY_OMV_WEBUI_ADMIN"
  _savedeployconf DEPLOY_OMV_SSH_USER "$DEPLOY_OMV_SSH_USER"

  _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'CertificateMgmt' 'getList' '{\"start\": 0, \"limit\": -1}' | jq -r '.data[] | select(.name==\"/CN='$_cdomain'\") | .uuid'"
  # shellcheck disable=SC2086
  _uuid=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")
  _debug _command "$_command"

  if [ -z "$_uuid" ]; then
    _info "[OMV deploy-hook] Domain $_cdomain has no certificate in openmediavault, creating it!"
    _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'CertificateMgmt' 'create' '{\"cn\": \"test.example.com\", \"size\": 4096, \"days\": 3650, \"c\": \"\", \"st\": \"\", \"l\": \"\", \"o\": \"\", \"ou\": \"\", \"email\": \"\"}' | jq -r '.uuid'"
    # shellcheck disable=SC2086
    _uuid=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")
    _debug _command "$_command"

    if [ -z "$_uuid" ]; then
      _err "[OMB deploy-hook] An error occured while creating the certificate"
      return 1
    fi
  fi

  _info "[OMV deploy-hook] Domain $_cdomain has uuid: $_uuid"
  _fullchain=$(jq <"$_cfullchain" -aRs .)
  _key=$(jq <"$_ckey" -aRs .)

  _debug _fullchain "$_fullchain"
  _debug _key "$_key"

  _info "[OMV deploy-hook] Updating key and certificate in openmediavault"
  _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'CertificateMgmt' 'set' '{\"uuid\":\"$_uuid\", \"certificate\":$_fullchain, \"privatekey\":$_key, \"comment\":\"acme.sh deployed $(date)\"}'"
  # shellcheck disable=SC2029
  _result=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")

  _debug _command "$_command"
  _debug _result "$_result"

  _info "[OMV deploy-hook] Asking openmediavault to apply changes... (this could take some time, hang in there)"
  _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'Config' 'applyChanges' '{\"modules\":[], \"force\": false}'"
  # shellcheck disable=SC2029
  _result=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")

  _debug _command "$_command"
  _debug _result "$_result"

  _info "[OMV deploy-hook] Asking nginx to reload"
  _command="nginx -s reload"
  # shellcheck disable=SC2029
  _result=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")

  _debug _command "$_command"
  _debug _result "$_result"

  return 0
}
