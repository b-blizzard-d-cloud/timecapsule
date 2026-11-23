#!/bin/bash
# nat-down.sh: removes what nat-up.sh created.
# Order matters: route -> NAT Gateway -> wait for "deleted" -> Elastic IP (an address held by a gateway cannot be released).
# Option --keep-route leaves the (then Blackhole) route 0.0.0.0/0 in place, for demonstration only.
set -euo pipefail

AWS_REGION=${AWS_REGION:-eu-central-1}
export AWS_REGION AWS_DEFAULT_REGION=$AWS_REGION AWS_PAGER=""
STATE_FILE=${STATE_FILE:-$(cd "$(dirname "$0")" && pwd)/.nat-state}
RELEASE_ATTEMPTS=10
RELEASE_PAUSE=15

log() { printf '[%s] %s\n' "$(date -u '+%H:%M:%SZ')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }
usage() { echo "usage: $0 [--keep-route] [-h]   (settings: AWS_REGION, STATE_FILE)"; }
on_error() { log "step failed on line $1; the state file is kept, run the script again" >&2; }
trap 'on_error $LINENO' ERR

KEEP_ROUTE=0
case "${1:-}" in -h|--help) usage; exit 0;; --keep-route) KEEP_ROUTE=1;; "") ;; *) usage; exit 2;; esac
[ -f "$STATE_FILE" ] || die "state file $STATE_FILE not found: nothing to remove"
# shellcheck disable=SC1090
. "$STATE_FILE"
[ -n "${NAT_ID:-}" ] && [ -n "${ALLOC_ID:-}" ] && [ -n "${PRIVATE_RT_ID:-}" ] || die "state file is incomplete"

retry() { # attempts pause command...
  local n=$1 pause=$2 i=1; shift 2
  until "$@"; do
    [ "$i" -ge "$n" ] && return 1
    log "    attempt $i of $n failed, next in ${pause} s"; i=$((i + 1)); sleep "$pause"
  done
}

if [ "$KEEP_ROUTE" -eq 1 ]; then
  log "1/4 route kept (--keep-route)"
else
  log "1/4 deleting route 0.0.0.0/0 from $PRIVATE_RT_ID"
  aws ec2 delete-route --route-table-id "$PRIVATE_RT_ID" --destination-cidr-block 0.0.0.0/0
fi

log "2/4 deleting NAT Gateway $NAT_ID"
aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" >/dev/null

log "3/4 waiting until the gateway is deleted"
aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"

log "4/4 releasing Elastic IP $ALLOC_ID (up to $RELEASE_ATTEMPTS attempts)"
retry "$RELEASE_ATTEMPTS" "$RELEASE_PAUSE" aws ec2 release-address --allocation-id "$ALLOC_ID" \
  || die "Elastic IP $ALLOC_ID was not released: release it manually, it is billed while allocated"

rm -f "$STATE_FILE"
log "done: no NAT Gateway and no NAT Elastic IP left"
