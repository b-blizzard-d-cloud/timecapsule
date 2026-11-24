#!/bin/bash
# LR5 task 8 (run ON app): user timecapsule + database. Password = DB_PASSWORD from .env, never printed.
set -euo pipefail
EP=${1:?usage: s08-user-db.sh <rds-endpoint>}
PW=$(sudo grep '^DB_PASSWORD=' /var/www/timecapsule/.env | cut -d= -f2-)
grep -q "^$EP:5432:\*:timecapsule:" ~/.pgpass 2>/dev/null || { printf '%s:5432:*:timecapsule:%s\n' "$EP" "$PW" >> ~/.pgpass; chmod 600 ~/.pgpass; }
psql -h "$EP" -U dbadmin -d postgres -v ON_ERROR_STOP=1 -v pw="$PW" <<'SQL'
CREATE USER timecapsule;
\set QUIET on
ALTER USER timecapsule PASSWORD :'pw';
\set QUIET off
GRANT timecapsule TO dbadmin;
CREATE DATABASE timecapsule OWNER timecapsule;
SQL
