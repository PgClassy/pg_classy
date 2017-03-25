\set ECHO none
BEGIN;
CREATE EXTENSION IF NOT EXISTS cat_tools; -- object_reference depends on this
CREATE EXTENSION IF NOT EXISTS count_nulls; -- object_reference depends on this
CREATE EXTENSION IF NOT EXISTS object_reference;

CREATE EXTENSION IF NOT EXISTS trunklet;

\i test/pgxntool/psql.sql

-- Need to create this manually
CREATE SCHEMA classy;

\echo
\echo INSTALL
\i sql/classy.sql

\echo # TRANSACTION INTENTIONALLY LEFT OPEN
