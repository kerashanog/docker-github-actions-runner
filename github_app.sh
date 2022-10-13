#!/usr/bin/env bash

# Generate JWT for Github App
#
# Credit: 
#   https://gist.github.com/carestad/bed9cb8140d28fe05e67e15f667d98ad 

thisdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -o pipefail

# Download Github App private key
wget -O "${thisdir}/app.pem" "${APP_PRIVATE_KEY}"

# Change these variables:
app_id="${APP_ID}"
app_private_key="$(< $thisdir/app.pem)"

# Shared content to use as template
header='{
    "alg": "RS256",
    "typ": "JWT"
}'
payload_template='{}'

build_payload() {
        jq -c \
                --arg iat_str "$(date +%s)" \
                --arg app_id "${app_id}" \
        '
        ($iat_str | tonumber) as $iat
        | .iat = $iat
        | .exp = ($iat + 300)
        | .iss = ($app_id | tonumber)
        ' <<< "${payload_template}" | tr -d '\n'
}

b64enc() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
json() { jq -c . | LC_CTYPE=C tr -d '\n'; }
rs256_sign() { openssl dgst -binary -sha256 -sign <(printf '%s\n' "$1"); }

sign() {
    local algo payload sig
    algo=${1:-RS256}; algo=${algo^^}
    payload=$(build_payload) || return
    signed_content="$(json <<<"$header" | b64enc).$(json <<<"$payload" | b64enc)"
    sig=$(printf %s "$signed_content" | rs256_sign "$app_private_key" | b64enc)
    generated_jwt="${signed_content}.${sig}"

    app_installations_url="https://api.github.com/app/installations"
    app_installations_response=$(curl -sX GET -H "Authorization: Bearer  ${generated_jwt}" -H "Accept: application/vnd.github.v3+json" ${app_installations_url})
    access_token_url=$(echo $app_installations_response | jq '.[] | select (.app_id  == '${app_id}') .access_tokens_url' --raw-output)

    access_token_response=$(curl -sX POST -H "Authorization: Bearer  ${generated_jwt}" -H "Accept: application/vnd.github.v3+json" ${access_token_url})

    APP_TOKEN=$(echo $access_token_response | jq .token --raw-output)
	echo "{\"token\": \"${APP_TOKEN}\"}"
}

sign