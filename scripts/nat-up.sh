#!/bin/bash
# nat-up.sh: temporary NAT Gateway for private-a (LR3, task 13, variant B).
# Steps: allocate Elastic IP -> create NAT Gateway in public-a -> wait for "available"
#        -> default route 0.0.0.0/0 in private-rt -> save IDs to scripts/.nat-state.
# Requires AWS CLI credentials (profile via AWS_PROFILE or CloudShell role). Works with bash 3.2.
set -euo pipefail

AWS_REGION=${AWS_REGION:-eu-central-1}
export AWS_REGION AWS_DEFAULT_REGION=$AWS_REGION AWS_PAGER=""
PUBLIC_SUBNET_ID=${PUBLIC_SUBNET_ID:-subnet-0591624a4d9f0f6f8}   # timecapsule-dev-public-a
PRIVATE_RT_ID=${PRIVATE_RT_ID:-rtb-082f34909fe2d1887}            # timecapsule-dev-private-rt
STATE_FILE=${STATE_FILE:-$(cd "$(dirname "$0")" && pwd)/.nat-state}
OWNER=danametelska

log() { printf '[%s] %s\n' "$(date -u '+%H:%M:%SZ')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }
usage() { echo "usage: $0 [-h]   (creates the NAT Gateway; settings: AWS_REGION, PUBLIC_SUBNET_ID, PRIVATE_RT_ID, STATE_FILE)"; }
on_error() { log "step failed on line $1; check the state file $STATE_FILE and run nat-down.sh to clean up" >&2; }
trap 'on_error $LINENO' ERR

case "${1:-}" in -h|--help) usage; exit 0;; "") ;; *) usage; exit 2;; esac
[ -f "$STATE_FILE" ] && die "state file $STATE_FILE already exists: a NAT Gateway may be running (run nat-down.sh first)"

tags() { # resource-type name
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=timecapsule},{Key=Environment,Value=dev},{Key=Owner,Value=$OWNER},{Key=Lab,Value=lab3},{Key=Course,Value=cloud-computing},{Key=Group,Value=i2402}]"
}

log "1/5 allocating Elastic IP (timecapsule-dev-nat-a-eip)"
ALLOC_ID=$(aws ec2 allocate-address --domain vpc --tag-specifications "$(tags elastic-ip timecapsule-dev-nat-a-eip)" --query AllocationId --output text)
log "    allocation $ALLOC_ID"

log "2/5 creating NAT Gateway timecapsule-dev-nat-a in $PUBLIC_SUBNET_ID"
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUBLIC_SUBNET_ID" --allocation-id "$ALLOC_ID" --connectivity-type public \
  --tag-specifications "$(tags natgateway timecapsule-dev-nat-a)" --query NatGateway.NatGatewayId --output text)
log "    gateway $NAT_ID"
# state is written at once, so that nat-down.sh can clean up even if a later step fails
printf 'NAT_ID=%s\nALLOC_ID=%s\nPRIVATE_RT_ID=%s\n' "$NAT_ID" "$ALLOC_ID" "$PRIVATE_RT_ID" > "$STATE_FILE"

log "3/5 waiting until the gateway is available (usually 2-3 minutes)"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

log "4/5 default route in $PRIVATE_RT_ID -> $NAT_ID"
if aws ec2 describe-route-tables --route-table-ids "$PRIVATE_RT_ID" \
     --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`] | length(@)' --output text | grep -qx 1; then
  log "    a route 0.0.0.0/0 exists (for example Blackhole after an earlier gateway): replacing it"
  aws ec2 replace-route --route-table-id "$PRIVATE_RT_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID"
else
  aws ec2 create-route --route-table-id "$PRIVATE_RT_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" >/dev/null
fi

log "5/5 state saved in $STATE_FILE"
PUBLIC_IP=$(aws ec2 describe-addresses --allocation-ids "$ALLOC_ID" --query 'Addresses[0].PublicIp' --output text)
log "done: NAT $NAT_ID, external address $PUBLIC_IP. Remove it with scripts/nat-down.sh when the work is finished."
