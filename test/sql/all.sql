\set ECHO none
\i test/pgxntool/setup.sql

/*
SET client_min_messages = debug;
SELECT no_plan();
SELECT * FROM _trunklet_test.test_process();
\du
*/
-- Needed for now due to bug in pgtap-core.sql
SET client_min_messages = WARNING;

SET search_path = _classy_test, tap, "$user";
SELECT * FROM runtests( '_classy_test'::name );
