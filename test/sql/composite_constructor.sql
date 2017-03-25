\set ECHO none
\i test/pgxntool/setup.sql

CREATE EXTENSION composite_constructor;

CREATE TYPE pg_temp.complex AS (a text, r float, b boolean, i float, c int);
ALTER TYPE complex
  DROP ATTRIBUTE a
  , DROP ATTRIBUTE b
  , DROP ATTRIBUTE c
;

CREATE TYPE "mid space" AS("c 1" pg_temp.complex, "c 2" pg_temp.complex);
CREATE TYPE top AS(mids "mid space"[], complex complex, t text);

CREATE FUNCTION pg_temp.get_classy(
) RETURNS _classy._class LANGUAGE sql AS $body$
SELECT *
  FROM _classy._class
  WHERE class_name = 'composite_constructor'
$body$;

CREATE FUNCTION pg_temp.sn(
) RETURNS name LANGUAGE sql IMMUTABLE AS $$
SELECT pg_my_temp_schema()::regnamespace::name
$$;

CREATE FUNCTION pg_temp.preprocess_body(
  composite text
) RETURNS text LANGUAGE sql AS $body$
SELECT trunklet.process(
      preprocess_template_id
      , json_object(array['composite',composite])
    )
    FROM pg_temp.get_classy()
$body$;
CREATE FUNCTION pg_temp.preprocess(
  composite text
) RETURNS json LANGUAGE sql AS $body$
SELECT trunklet.execute_into(
      preprocess_template_id
      , json_object(array['composite',composite])
    )
    FROM pg_temp.get_classy()
$body$;

SELECT plan(
  0

  + 2 -- Sanity check

  -- complex
  + 1 -- verify pre-process output
  + 2 -- instantiate
  + 5 -- sanity-check
  + 2 -- verify output

  -- top
  + 1 -- sanity
  + 1 -- instantiate
  + 1 -- sanity-check

  -- "mid space"
  + 1 -- sanity
  + 1 -- instantiate
  + 1 -- sanity-check

  -- verify results of top
  + 1
);

SELECT ok(
  exists(SELECT 1 FROM _classy._class WHERE class_name = 'composite_constructor')
  , 'composite_constructor exists'
);

/*
SELECT throws_ok(
  $$SELECT classy.instantiate('composite_constructor', 1, '{"composite": "int"}');$$
  , ''
);
*/

SELECT is(
  pg_temp.preprocess('pg_temp.complex')::jsonb
  , replace(
    '{"body": "SELECT (\n  r\n  , i\n)::pg_temp.complex", "arguments": "  r double precision\n  , i double precision", "composite_fqn": "pg_temp.complex", "comment_string": "Constructor function for composite type pg_temp.complex", "arguments with defaults": "  r double precision = NULL\n  , i double precision = NULL"}'
    , 'pg_temp'
    , pg_temp.sn()
  )::jsonb
  , 'Verify results of preprocessing template'
);
SELECT * FROM _classy.instance;
SELECT hasnt_function(
  pg_temp.sn()
  , 'complex', '{float,float}'::regtype[]::name[]
  , 'pg_temp.complex() does not exist'
);

SELECT lives_ok(
  $$SELECT classy.instantiate('composite_constructor', 1, '{"composite": "pg_temp.complex"}')$$
  , 'Instantiate pg_temp.complex'
);
SELECT throws_ok(
  $$SELECT classy.instantiate('composite_constructor', 1, '{"composite": "pg_temp.complex"}')$$
  , NULL
  , 'instance of composite_constructor already created'
  , 'Duplicate instantiation throws error'
);

SELECT has_function(
  pg_temp.sn(), 'complex', '{float,float}'::regtype[]::name[]
  , 'pg_temp.complex() does exist'
);
SELECT function_lang_is(
  pg_temp.sn(), 'complex', '{float,float}'::regtype[]::name[]
  , 'sql'
  , 'complex() is a SQL function'
);
SELECT function_returns(
  pg_temp.sn(), 'complex', '{float,float}'::regtype[]::name[]
  , 'complex'::regtype::text
  , 'complex() returns complex type'
);
\df function_isnt_strict
SELECT isnt_strict(
  pg_temp.sn(), 'complex', '{float,float}'::regtype[]::name[]
  , 'complex() is not strict'
);
SELECT volatility_is(
  pg_temp.sn(), 'complex', '{float,float}'::regtype[]::name[]
  , 'immutable'
  , 'complex() is immutable'
);

SELECT is(
  pg_temp.complex(2e-1,3e4)
  , (2e-1,3e4)::pg_temp.complex
  , 'complex() produces correct output'
);
SELECT is(
  pg_temp.complex()
  , (NULL,NULL)::pg_temp.complex
  , 'complex() works with no inputs'
);

/*
 * Test composite type "top"
 *
 * This is intentionally done before "mid space" to ensure there's no dependency on
 * having a constructor function.
 */

--CREATE TYPE top AS(mids "mid space"[], complex complex, t text);
SELECT hasnt_function(
  'top'
  , array['"mid space"[]'::regtype, 'complex', 'text']::name[]
  , 'top constructor should not exist'
);
SELECT lives_ok(
  $$SELECT classy.instantiate('composite_constructor', 1, '{"composite": "top"}')$$
  , 'Instantiate constructor for "top"'
);
SELECT has_function(
  'top'
  , array['"mid space"[]'::regtype, 'complex', 'text']::name[]
  , 'top constructor should exist'
);

/*
 * Test composite type ""mid space""
 */
--CREATE TYPE "mid space" AS("c 1" pg_temp.complex, "c 2" pg_temp.complex);
SELECT hasnt_function(
  'mid space'
  , '{complex,complex}'::regtype[]::name[]
  , '"mid space"() should not exist'
);
SELECT lives_ok(
  $$SELECT classy.instantiate('composite_constructor', 1, '{"composite": "\"mid space\""}')$$
  , 'Instantiate constructor for "mid space"'
);
SELECT has_function(
  'mid space'
  , '{complex,complex}'::regtype[]::name[]
  , '"mid space"() should exist'
);

/* Test output of top() */
SELECT is(
  top(
    array[
      "mid space"( "c 1" := pg_temp.complex(1,-1) )
      , "mid space"( "c 2" := pg_temp.complex(2,-2) )
    ]
    , pg_temp.complex(3,-3)
  )
  , (
      array[ -- "mid space"[]
        (
          (1,-1)::complex
          , NULL
        )::"mid space"
        , (
          NULL
          , (2,-2)::complex
        )::"mid space"
      ]
      , (3,-3)::complex
      , NULL
  )::top
  , 'Verify results of top()'
);

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2
