-- Note: pgTap is loaded by setup.sql

-- ... But we need to do it here because test_factory_pgtap needs it
\i test/pgxntool/tap_setup.sql

-- Add any test dependency statements here

-- Squelch warnings about already-exists
SET client_min_messages = WARNING;
CREATE EXTENSION IF NOT EXISTS trunklet;
CREATE EXTENSION IF NOT EXISTS "trunklet-format";
CREATE EXTENSION IF NOT EXISTS test_factory;
CREATE EXTENSION IF NOT EXISTS test_factory_pgtap;
SET client_min_messages = NOTICE;

-- No IF NOT EXISTS because we'll be confused if we're not loading the new stuff
CREATE EXTENSION classy;

\i test/core/functions.sql
