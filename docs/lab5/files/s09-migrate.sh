#!/bin/bash
# LR5 task 9 (run ON app). App must NOT be opened from the dump until the CNAME is switched (task 10).
set -euo pipefail
EP=${1:?usage: s09-migrate.sh <rds-endpoint>}
cd ~
# password of the old DB for this session only (from .env, never printed)
export PGPASSWORD=$(sudo grep '^DB_PASSWORD=' /var/www/timecapsule/.env | cut -d= -f2-)
echo "== dump from db.timecapsule.internal"; date -u '+%F %T UTC'
pg_dump -h db.timecapsule.internal -U timecapsule -d timecapsule --no-owner --no-privileges -f timecapsule.sql
ls -l timecapsule.sql
echo "== load into RDS"
env -u PGPASSWORD psql -h "$EP" -U timecapsule -d timecapsule -v ON_ERROR_STOP=1 -q -f timecapsule.sql
for t in users capsules; do
  a=$(psql -h db.timecapsule.internal -U timecapsule -d timecapsule -Atc "select count(*) from $t")
  b=$(env -u PGPASSWORD psql -h "$EP" -U timecapsule -d timecapsule -Atc "select count(*) from $t")
  echo "$t: db-server=$a rds=$b $([ "$a" = "$b" ] && echo MATCH || echo MISMATCH)"
done
rm -f timecapsule.sql; ls timecapsule.sql 2>&1 || true
