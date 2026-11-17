#!/usr/bin/env bash
# Very simple script used to check the various health endpoints of differing shapes.
# Takes 2 arguments, the first is the URL to check, the second is a jq argument or JSON array of checks.
#
# Usage:
#   Single check:   ./script.sh <url> '.status == "ok"'
#   Multiple checks: ./script.sh <url> '[{"name": "status", "query": ".status == \"ok\""}, {"name": "ready", "query": ".ready"}]'
#   Base64 encoded: ./script.sh <url> 'base64:eyJuYW1lIjoib2siLCJxdWVyeSI6Ii5vayJ9'
#
# Debug mode:
#   DEBUG=1 ./script.sh <url> <jq_arg>

debug() {
    [ "$DEBUG" = "1" ] && echo "[DEBUG] $*"
}

validate_commands() {
    COMMANDS=("curl" "jq" "base64")
    MISSING_COMMANDS=()
    for cmd in "${COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            MISSING_COMMANDS+=("$cmd")
        fi
    done
    if [ ${#MISSING_COMMANDS[@]} -ne 0 ]; then
        echo "Error: The following required commands are missing: ${MISSING_COMMANDS[*]}"
        echo "Please install them and try again."
        exit 1
    fi
}

parse_args() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: $0 <url> <jq_arg|checks_json|base64:encoded>"
        exit 1
    fi

    ENDPOINT="$1"
    JQ_ARG="$2"

    # Decode base64 if prefixed with 'base64:'
    if [[ "$JQ_ARG" == base64:* ]]; then
        debug "Base64 encoded input detected"
        local encoded="${JQ_ARG#base64:}"
        JQ_ARG=$(echo "$encoded" | base64 -d 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "Error: Failed to decode base64 string"
            exit 1
        fi
        debug "Decoded: $JQ_ARG"
    fi
}

validate_jq_arg() {
    local jq_arg="$1"

    debug "Validating jq arguments"

    # Try to parse as JSON first
    if ! echo "$jq_arg" | jq . >/dev/null 2>&1; then
        echo "Error: JQ argument is not valid JSON"
        echo "Received: $jq_arg"
        exit 1
    fi

    # Check if it's an array (multiple checks)
    if echo "$jq_arg" | jq -e 'type == "array"' >/dev/null 2>&1; then
        debug "Validating multiple checks"

        local count
        count=$(echo "$jq_arg" | jq '. | length')
        debug "Found $count checks"

        # Validate each check has required fields and valid queries
        local check_num=0
        while IFS= read -r check; do
            ((check_num++))
            local name
            local query
            name=$(echo "$check" | jq -r '.name // empty')
            query=$(echo "$check" | jq -r '.query // empty')

            if [ -z "$name" ]; then
                echo "Error: Check $check_num missing 'name' field"
                exit 1
            fi
            if [ -z "$query" ]; then
                echo "Error: Check $check_num (name: $name) missing 'query' field"
                exit 1
            fi

            debug "Check $check_num: name='$name', query='$query'"

            if ! echo "{}" | jq "$query" >/dev/null 2>&1; then
                echo "Error: Check $check_num (name: $name) has invalid jq query: $query"
                exit 1
            fi
        done < <(echo "$jq_arg" | jq -c '.[]')
    else
        # Single check - validate it's valid jq syntax
        debug "Validating single jq query: $jq_arg"

        if ! echo "{}" | jq "$jq_arg" >/dev/null 2>&1; then
            echo "Error: Invalid jq query: $jq_arg"
            exit 1
        fi
    fi

    debug "JQ validation passed"
}

# Fetch the response from the endpoint with a retry mechanism
# Retries up to 3 times with a 5-second delay between attempts.
fetch_response() {
    local url="$1"
    local jq_arg="$2"
    local max_retries=3
    local attempt=1
    local delay=5
    local response
    local http_status

    debug "Starting health check for $url"
    debug "JQ args: $jq_arg"

    while [ $attempt -le $max_retries ]; do
        debug "Attempt $attempt/$max_retries"
        response=$(curl -s --max-time 10 -w "%{http_code}" "$url")
        http_status="${response:(-3)}"
        response="${response%???}"

        debug "HTTP status: $http_status"
        debug "Response body length: ${#response}"

        if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
            debug "Got 2xx response, checking jq condition"
            if echo "$jq_arg" | jq -e 'type == "array"' >/dev/null 2>&1; then
                debug "Multiple checks detected"
                check_multiple "$response" "$jq_arg" && return 0
            else
                debug "Single check mode"
                local output
                output=$(echo "$response" | jq -e "$jq_arg" 2>/dev/null)
                debug "JQ output: $output"
                if [ "$output" != "false" ] && [ "$output" != "null" ]; then
                    echo "$output"
                    debug "Check passed, returning success"
                    return 0
                else
                    debug "Check failed (false or null), will retry"
                fi
            fi
        else
            echo "Attempt $attempt: Received HTTP status $http_status. Retrying in $delay seconds..."
            sleep $delay
            ((attempt++))
        fi
    done

    echo "Error: Failed to fetch a successful response from $url after $max_retries attempts."
    echo "Last received HTTP response: $http_status"
    exit 1
}

check_multiple() {
    local response="$1"
    local checks_json="$2"

    debug "Checking multiple conditions"

    # Use process substitution to avoid subshell
    while IFS= read -r check; do
        local name
        name=$(echo "$check" | jq -r '.name')
        local query
        query=$(echo "$check" | jq -r '.query')

        debug "Checking: $name with query: $query"

        local result
        local exit_code
        result=$(echo "$response" | jq "$query" 2>/dev/null)
        exit_code=$?

        debug "$name result: $result (exit: $exit_code)"

        if [ $exit_code -ne 0 ]; then
            echo "✗ $name: jq parse error"
            return 1
        fi

        if echo "$result" | jq -e . >/dev/null 2>&1 && [ "$result" != "false" ] && [ "$result" != "null" ]; then
            echo "✓ $name: $result"
        else
            echo "✗ $name: $result"
            return 1
        fi
    done < <(echo "$checks_json" | jq -r '.[] | @json')

    debug "All checks passed"
    return 0
}

validate_commands
parse_args "$@"
validate_jq_arg "$JQ_ARG"
fetch_response "$ENDPOINT" "$JQ_ARG"
