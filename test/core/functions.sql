CREATE SCHEMA _classy_test;
SET search_path = _classy_test, tap, "$user";

/*
 * NOTE! DO NOT use CREATE OR REPLACE FUNCTION in here. If you do that and
 * accidentally try to define the same function twice you'll never detect that
 * mistake!
 */

/*
CREATE FUNCTION test_
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
BEGIN
END
$body$;
*/

/*
 * schemas
 */
CREATE FUNCTION test_schemas
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
BEGIN
  RETURN NEXT schema_privs_are(
    'classy'
    , 'public'
    , array[ 'USAGE' ]
  );

  RETURN NEXT schema_privs_are(
    '_classy'
    , 'public'
    , array[ NULL ]
  );
  RETURN NEXT schema_privs_are(
    '_classy'
    , 'classy__dependency'
    , array[ 'USAGE' ]
  );

  RETURN NEXT schema_privs_are(
    '_classy_functions'
    , 'public'
    , array[ 'USAGE' ]
  );
END
$body$;

/*
 * LANGUAGE FACTORY
 */

-- Not sure what we want here for classy... maybe just CREATE EXTENSION "trunklet-format" since this idiotic^Wsimple language probably won't work.
CREATE FUNCTION bogus_language_name(
) RETURNS text LANGUAGE sql AS $$SELECT 'bogus template language that does not exist'::text$$;
CREATE FUNCTION get_test_language_name(
) RETURNS text LANGUAGE sql AS $$SELECT 'Our internal test language'::text$$;
CREATE FUNCTION get_test_language_id(
) RETURNS int LANGUAGE plpgsql AS $body$
BEGIN
  BEGIN
  PERFORM classy.template_language__add(
      get_test_language_name()
      , parameter_type := 'text[]'
      , template_type := 'text'
      , process_function_options := 'LANGUAGE plpgsql'
      , process_function_body := $process$
DECLARE
  v_args CONSTANT text := array_to_string( array( SELECT ', ' || quote_nullable(a) FROM unnest(parameters::text[]) a(a) ), '' );
  sql CONSTANT text := format( 'SELECT format( %L%s )', template::text, v_args );
  v_return text;
BEGIN
  RAISE DEBUG 'EXECUTE INTO using sql %', sql;
  EXECUTE sql INTO v_return;
  RETURN v_return;
END
$process$
      , extract_parameters_options := 'LANGUAGE sql'
      , extract_parameters_body := $extract$
SELECT array(
    SELECT (parameters::text[])[i]
      FROM generate_subscripts( parameters::text[], 1 ) i
      WHERE i = ANY( extract_list::int[] )
  )::variant.variant
$extract$
    );
  EXCEPTION
    -- TODO: incorrect return value
    WHEN no_data_found OR unique_violation THEN
      NULL;
  END;
  RETURN _classy.language__get_id( get_test_language_name() );
END
$body$;


-- vi: expandtab sw=2 ts=2
