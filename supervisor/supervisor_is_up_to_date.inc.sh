# Checks if Supervisor is up-to-date (3.0+ or newer)
# Newer versions have the "kill forks" bug fixed and other improvements
function supervisor_is_up_to_date() {
    local SUPERVISORD=supervisord

    # Older Supervisor versions (pre-"3.0a...") don't support the "-v" flag
    $SUPERVISORD -v &> /dev/null || {
        return 1
    }

    # Refuse to have something to do with "3.0a" and "3.0b" versions
    local SUPERVISORD_VERSION=`$SUPERVISORD -v`
    if [[ "$SUPERVISORD_VERSION" == 3.0a ]] || [[ "$SUPERVISORD_VERSION" == 3.0b* ]]; then
        return 1
    fi

    # 3.0 or newer at this point
    return 0
}

# Print a message and exit if supervisor is too old
function validate_supervisor_version() {
    if ! supervisor_is_up_to_date; then
        echo "Supervisor (supervisord) is too old. Please install version 3.0 or newer:"
        echo
        echo "    sudo apt-get remove -y supervisor"
        echo "    sudo easy_install supervisor"
        echo
        exit 1
    fi

}
