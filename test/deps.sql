-- Note: pgTap is loaded by setup.sql

-- Add any test dependency statements here

-- Squelch warnings about already-exists
SET client_min_messages = WARNING;
CREATE EXTENSION IF NOT EXISTS variant;
CREATE EXTENSION IF NOT EXISTS trunklet;
SET client_min_messages = NOTICE;

-- No IF NOT EXISTS because we'll be confused if we're not loading the new stuff
--\i sql/trunklet.sql
CREATE EXTENSION classy;

\i test/core/functions.sql
