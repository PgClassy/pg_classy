\set ECHO none
CREATE EXTENSION IF NOT EXISTS variant;
CREATE EXTENSION IF NOT EXISTS trunklet;

\i test/pgxntool/psql.sql

BEGIN;
-- Need to create this manually
CREATE SCHEMA classy;

\echo
\echo INSTALL
\i sql/classy.sql

\echo
\echo UNINSTALL
\i sql/uninstall_classy.sql
ROLLBACK;
