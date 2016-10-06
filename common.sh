function die {
    echo >&2 "$@"
    exit 1
}

function log_info {
  echo "===> ${1}"
}
