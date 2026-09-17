function log_write {
    local message=$1
    local level=${2:-i}
    local type
    case $level in
        i) type="INFO   " ;;
        e) type="ERROR  " ;;
        n) type="NOTICE " ;;
        *) type="INFO   " ;;
    esac
    echo "$(date '+%Y-%m-%d %H:%M:%S') -=- ${type}: ${message}" | tee -a "$LOGFILE.log"
}

# require_cmd <cmd> [<cmd> ...]
# Fails fast with a clear message instead of trying to install things
# interactively — this script runs unattended from cron.
function require_cmd {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        log_write "Required command(s) not found: ${missing[*]}. Install them first (e.g. apt install ${missing[*]})." e
        exit 2
    fi
}

# require_var <NAME> [<NAME> ...]
# Fails fast if a required config variable is unset or empty.
function require_var {
    local missing=()
    for name in "$@"; do
        if [[ -z "${!name:-}" ]]; then
            missing+=("$name")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        log_write "Missing required config value(s): ${missing[*]}. Check mailcow-backup.env." e
        exit 2
    fi
}
