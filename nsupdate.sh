#!/usr/bin/env sh
# Update INWX DNS records with the current WAN IP, including TOTP-based 2FA.
# Based on https://github.com/chrisb86/nsupdate (MIT License).

set -u

chat() {
    message_type=$1
    message=$2
    log="${nsupdate_log_dir}/${nsupdate_log_file}"
    log_date=$(date "+${log_date_format}")
    line="[${log_date}]"

    case "$message_type" in
        0) line="$line [INFO] $message" ;;
        1) line="$line [ERROR] $message" ;;
        2) [ "$VERBOSE" = "true" ] || return 0; line="$line [INFO] $message" ;;
        3) [ "$DEBUG" = "true" ] || return 0; line="$line [DEBUG] $message" ;;
        *) line="$line $message" ;;
    esac

    printf '%s\n' "$line" | tee -a "$log"
    [ "$message_type" -eq 1 ] && exit 1
    return 0
}

xml_escape() {
    printf '%s' "$1" | sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&apos;/g"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || chat 1 "Required command not found: $1"
}

init() {
    nsupdate_conf_file="nsupdate.conf"
    basedir="${BASEDIR:-/usr/local/etc}"
    nsupdate_conf_dir="${NSUPDATE_CONF_DIR:-${basedir}/nsupdate}"

    [ -f "./${nsupdate_conf_file}" ] && . "./${nsupdate_conf_file}"
    [ -f "${nsupdate_conf_dir}/${nsupdate_conf_file}" ] && . "${nsupdate_conf_dir}/${nsupdate_conf_file}"

    VERBOSE="${VERBOSE:-false}"
    DEBUG="${DEBUG:-false}"
    [ "$DEBUG" = "true" ] && set -x

    nsupdate_confd_dir="${NSUPDATE_CONFD_DIR:-${nsupdate_conf_dir}/conf.d}"
    log_date_format="${LOG_DATE_FORMAT:-%Y-%m-%d %H:%M:%S}"
    nsupdate_log_dir="${NSUPDATE_LOG_DIR:-/var/log/nsupdate}"
    nsupdate_log_file="${NSUPDATE_LOG_FILE:-nsupdate.log}"
    tmp_dir="${NSUPDATE_TMP_DIR:-/tmp}"
    nsupdate_conf_extension="${NSUPDATE_CONF_EXTENSION:-.conf}"
    nsupdate_record_type="${NSUPDATE_RECORD_TYPE:-A}"
    nsupdate_record_ttl="${NSUPDATE_RECORD_TTL:-300}"
    inwx_api="${NSUPDATE_INWX_API:-https://api.domrobot.com/xmlrpc/}"
    inwx_nameserver="${NSUPDATE_INWX_NAMESERVER:-ns.inwx.de}"
    ip_check_site="${NSUPDATE_IP_CHECK_SITE:-https://api64.ipify.org}"
    curl_timeout="${NSUPDATE_CURL_TIMEOUT:-30}"

    mkdir -p "$nsupdate_log_dir" || exit 1
    require_command curl
    require_command xmllint
    require_command mktemp

    wan_ip4=$(curl --silent --show-error --fail --max-time "$curl_timeout" -4 "$ip_check_site" 2>/dev/null || true)
    wan_ip6=$(curl --silent --show-error --fail --max-time "$curl_timeout" -6 "$ip_check_site" 2>/dev/null || true)
    chat 2 "WAN IPv4: ${wan_ip4:-unavailable}"
    chat 2 "WAN IPv6: ${wan_ip6:-unavailable}"
}

xml_value() {
    file=$1
    xpath=$2
    xmllint --xpath "string(${xpath})" "$file" 2>/dev/null || true
}

api_code() {
    xml_value "$1" '/methodResponse/params/param/value/struct/member[name="code"]/value/*[1]'
}

api_message() {
    xml_value "$1" '/methodResponse/params/param/value/struct/member[name="msg"]/value/*[1]'
}

api_call() {
    method=$1
    members=$2
    output_file=$3
    payload="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<methodCall>
  <methodName>${method}</methodName>
  <params><param><value><struct>${members}</struct></value></param></params>
</methodCall>"

    curl --silent --show-error --fail --max-time "$curl_timeout" \
        --cookie "$inwx_cookie_file" \
        --cookie-jar "$inwx_cookie_file" \
        --header 'Content-Type: application/xml' \
        --request POST \
        --data "$payload" \
        --output "$output_file" \
        "$inwx_api" || chat 1 "HTTP request to INWX failed for ${method}."

    code=$(api_code "$output_file")
    message=$(api_message "$output_file")
    [ "$code" = "1000" ] || chat 1 "INWX ${method} failed: ${message:-unknown error} (${code:-no code})"
}

member_string() {
    name=$(xml_escape "$1")
    value=$(xml_escape "$2")
    printf '<member><name>%s</name><value><string>%s</string></value></member>' "$name" "$value"
}

member_int() {
    name=$(xml_escape "$1")
    value=$(xml_escape "$2")
    printf '<member><name>%s</name><value><int>%s</int></value></member>' "$name" "$value"
}

generate_totp() {
    if [ -n "${INWX_TOTP_COMMAND:-}" ]; then
        sh -c "$INWX_TOTP_COMMAND"
        return
    fi

    command -v oathtool >/dev/null 2>&1 || chat 1 "INWX requires 2FA, but oathtool is not installed and INWX_TOTP_COMMAND is not configured."
    oathtool --totp -b "$inwx_shared_secret"
}

inwx_login() {
    inwx_cookie_file=$(mktemp "${tmp_dir%/}/nsupdate-cookie.XXXXXX") || chat 1 "Could not create cookie file."
    chmod 600 "$inwx_cookie_file"
    login_file=$(mktemp "${tmp_dir%/}/nsupdate-login.XXXXXX") || chat 1 "Could not create login response file."

    members="$(member_string user "$inwx_user")$(member_string pass "$inwx_password")$(member_string lang en)"
    api_call account.login "$members" "$login_file"

    tfa=$(xml_value "$login_file" '/methodResponse/params/param/value/struct/member[name="resData"]/value/struct/member[name="tfa"]/value/*[1]')
    [ -n "$tfa" ] || tfa=$(xml_value "$login_file" '/methodResponse/params/param/value/struct/member[name="tfa"]/value/*[1]')
    rm -f "$login_file"

    case "$tfa" in
        ""|NONE|none) chat 3 "INWX session authenticated without 2FA." ;;
        GOOGLE-AUTH|TOTP)
            [ -n "$inwx_shared_secret" ] || chat 1 "INWX requires TOTP 2FA, but no shared secret is configured."
            tan=$(generate_totp)
            [ -n "$tan" ] || chat 1 "Could not generate the INWX TOTP code."
            unlock_file=$(mktemp "${tmp_dir%/}/nsupdate-unlock.XXXXXX") || chat 1 "Could not create unlock response file."
            api_call account.unlock "$(member_string tan "$tan")" "$unlock_file"
            rm -f "$unlock_file"
            unset tan
            chat 3 "INWX session unlocked with TOTP 2FA."
            ;;
        *) chat 1 "Unsupported INWX two-factor method: ${tfa}" ;;
    esac
}

inwx_logout() {
    [ -n "${inwx_cookie_file:-}" ] || return 0
    if [ -f "$inwx_cookie_file" ]; then
        logout_file=$(mktemp "${tmp_dir%/}/nsupdate-logout.XXXXXX" 2>/dev/null || true)
        if [ -n "$logout_file" ]; then
            # Logout failures are intentionally non-fatal during cleanup.
            payload='<?xml version="1.0" encoding="UTF-8"?><methodCall><methodName>account.logout</methodName><params><param><value><struct/></value></param></params></methodCall>'
            curl --silent --max-time "$curl_timeout" --cookie "$inwx_cookie_file" --cookie-jar "$inwx_cookie_file" \
                --header 'Content-Type: application/xml' --request POST --data "$payload" --output "$logout_file" "$inwx_api" >/dev/null 2>&1 || true
            rm -f "$logout_file"
        fi
        rm -f "$inwx_cookie_file"
    fi
    unset inwx_cookie_file
}

cleanup() {
    inwx_logout
}
trap cleanup EXIT HUP INT TERM

get_domain_info() {
    response_file=$(mktemp "${tmp_dir%/}/nsupdate-info.XXXXXX") || chat 1 "Could not create nameserver.info response file."
    members="$(member_string domain "$main_domain")$(member_string name "$domain")$(member_string type "$record_type")"
    api_call nameserver.info "$members" "$response_file"

    inwx_domain_ip=$(xml_value "$response_file" '/methodResponse/params/param/value/struct/member[name="resData"]/value/struct/member[name="record"]/value/array/data/value[1]/struct/member[name="content"]/value/*[1]')
    inwx_domain_id=$(xml_value "$response_file" '/methodResponse/params/param/value/struct/member[name="resData"]/value/struct/member[name="record"]/value/array/data/value[1]/struct/member[name="id"]/value/*[1]')
    rm -f "$response_file"

    if [ -z "$inwx_domain_id" ]; then
        chat 2 "DNS record ${domain} [${record_type}] does not exist yet."
    fi
}

get_domain_wan_ip() {
    if [ -n "${WAN_IP_COMMAND:-}" ]; then
        wan_ip=$(sh -c "$WAN_IP_COMMAND") || chat 1 "WAN_IP_COMMAND failed for ${domain}."
        chat 2 "Using WAN_IP_COMMAND for ${domain}."
    elif [ "$record_type" = "AAAA" ]; then
        wan_ip=$wan_ip6
    else
        wan_ip=$wan_ip4
    fi

    [ -n "$wan_ip" ] || chat 1 "Could not determine WAN IP for ${domain} [${record_type}]."
}

create_record() {
    response_file=$(mktemp "${tmp_dir%/}/nsupdate-create.XXXXXX") || chat 1 "Could not create createRecord response file."
    members="$(member_string domain "$main_domain")$(member_string name "$domain")$(member_string type "$record_type")$(member_string content "$wan_ip")$(member_int ttl "$record_ttl")"
    api_call nameserver.createRecord "$members" "$response_file"
    inwx_domain_id=$(xml_value "$response_file" '/methodResponse/params/param/value/struct/member[name="resData"]/value/struct/member[name="id"]/value/*[1]')
    rm -f "$response_file"
}

update_record() {
    response_file=$(mktemp "${tmp_dir%/}/nsupdate-update.XXXXXX") || chat 1 "Could not create update response file."
    members="$(member_string id "$inwx_domain_id")$(member_string content "$wan_ip")$(member_int ttl "$record_ttl")"
    api_call nameserver.updateRecord "$members" "$response_file"
    rm -f "$response_file"
}

reset_record_variables() {
    unset INWX_USER INWX_PASSWORD INWX_SHARED_SECRET INWX_TOTP_COMMAND
    unset MAIN_DOMAIN DOMAIN RECORD_TYPE RECORD_TTL TYPE TTL WAN_IP_COMMAND INWX_DOMAIN_ID
    unset inwx_user inwx_password inwx_shared_secret main_domain domain record_type record_ttl
    unset inwx_domain_id inwx_domain_ip wan_ip
}

process_record() {
    config_file=$1
    reset_record_variables
    . "$config_file"
    chat 2 "Loading config file ${config_file}"

    inwx_user="${INWX_USER:-${NSUPDATE_INWX_USER:-}}"
    inwx_password="${INWX_PASSWORD:-${NSUPDATE_INWX_PASSWORD:-}}"
    inwx_shared_secret="${INWX_SHARED_SECRET:-${NSUPDATE_INWX_SHARED_SECRET:-}}"
    main_domain="${MAIN_DOMAIN:-}"
    domain="${DOMAIN:-}"
    record_type="${RECORD_TYPE:-${TYPE:-$nsupdate_record_type}}"
    record_ttl="${RECORD_TTL:-${TTL:-$nsupdate_record_ttl}}"

    [ -n "$inwx_user" ] || chat 1 "No INWX username configured for ${config_file}."
    [ -n "$inwx_password" ] || chat 1 "No INWX password configured for ${config_file}."
    [ -n "$main_domain" ] || chat 1 "MAIN_DOMAIN is missing in ${config_file}."
    [ -n "$domain" ] || chat 1 "DOMAIN is missing in ${config_file}."
    case "$record_type" in A|AAAA) ;; *) chat 1 "Unsupported record type ${record_type} in ${config_file}." ;; esac
    [ "$record_ttl" -ge 300 ] 2>/dev/null || chat 1 "RECORD_TTL must be an integer of at least 300."

    inwx_login
    get_domain_info
    get_domain_wan_ip

    chat 2 "DOMAIN: ${domain}"
    chat 2 "RECORD TYPE: ${record_type}"
    chat 2 "RECORD TTL: ${record_ttl}"
    chat 2 "INWX DOMAIN ID: ${inwx_domain_id:-not existing}"
    chat 2 "INWX IP: ${inwx_domain_ip:-not set}"

    if [ -z "${inwx_domain_id:-}" ]; then
        chat 0 "Creating DNS record for ${domain} [${record_type}] with IP ${wan_ip}."
        create_record
        chat 0 "DNS record for ${domain} [${record_type}] created successfully${inwx_domain_id:+ with ID ${inwx_domain_id}}."
    elif [ "${inwx_domain_ip:-}" != "$wan_ip" ]; then
        chat 0 "Updating DNS record for ${domain} [${record_type}]. Old IP: ${inwx_domain_ip:-none}. New IP: ${wan_ip}."
        update_record
    else
        chat 0 "No update required for ${domain} [${record_type}]."
    fi

    inwx_logout
}

init

set -- "${nsupdate_confd_dir}"/*"${nsupdate_conf_extension}"
[ -e "$1" ] || chat 1 "Could not find configuration files in ${nsupdate_confd_dir}."
for config_file in "$@"; do
    process_record "$config_file"
done
