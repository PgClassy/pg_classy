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
  /*
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
  */
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
  )::text
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


CREATE FUNCTION get_test_class(
) RETURNS text LANGUAGE sql AS $$SELECT 'pg_classy test create function'::text$$;

SELECT tf.register(
  '_classy._class'
  , array[
  row(
    'base'
    , format(
        $tf_regsiter$
          INSERT INTO _classy._class(
            class_name
            , class_version
            , unique_parameters_extract_list
            , creation_template_id
            , preprocess_template_id
          ) VALUES(
            %1$L
            , 1
            , '{function_name, arguments}'
            , trunklet.template__add(
              'format'
              , 'pg_classy: creation template for ' || %1$L
              , 
$template$
%2$s
$template$
            )
            , trunklet.template__add(
              'format'
              , 'pg_classy: pre-process template for ' || %1$L
              , 
$template$
%3$s
$template$
            )
          )
            RETURNING *
      $tf_regsiter$
      , get_test_class()
      , $template$
CREATE OR REPLACE FUNCTION %function_name%s(
%arguments%s
) RETURNS %returns%s
LANGUAGE %language%s
%options%s AS 
%body%L;
%comment_code%s
$template$
      , $preprocess$
SELECT json_object( array[
  'function_name', %function_name%L
  , 'arguments', %arguments%L
  , 'returns', %returns%L
  , 'language', %language%L
  , 'options', %options%L
  , 'body', %body%L
  , 'comment_code', coalesce(
    %comment_code%OL
    , CASE WHEN nullif(%comment%OL, '') IS NOT NULL THEN
        format(
          'COMMENT ON FUNCTION %%s(%%s) IS %%L;'
          , %function_name%L
          , %arguments%L
          , %comment%OL
        )
      END
    , ''
  )
  ] )
$preprocess$
    )
  )::tf.test_set
  ]
);

CREATE TYPE params AS (
  function_name text
  , arguments text
  , returns text
  , language text
  , options text
  , body text
  , comment text
);
CREATE FUNCTION params(
  function_name text = NULL
  , arguments text = NULL
  , returns text = NULL
  , language text = NULL
  , options text = NULL
  , body text = NULL
  , comment text = NULL
) RETURNS params LANGUAGE sql IMMUTABLE AS $body$
SELECT (
  function_name
  , arguments
  , returns
  , language
  , options
  , body
  , comment
)::params
$body$;
CREATE FUNCTION params_json(
  function_name text = NULL
  , arguments text = NULL
  , returns text = NULL
  , language text = 'sql'
  , options text = ''
  , body text = NULL
  , comment text = NULL
) RETURNS json LANGUAGE sql IMMUTABLE AS $body$
SELECT row_to_json( params(
  function_name
  , arguments
  , returns
  , language
  , options
  , body
  , comment
) );
$body$;
CREATE FUNCTION def_params
() RETURNS params LANGUAGE sql IMMUTABLE AS $body$
SELECT params(
  'classy_test.test_function'
  , 'a int, b int'
  , 'int'
  , body := 'SELECT a+b'
  , comment := 'test function'
)
$body$;

CREATE FUNCTION test_preprocess
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
  args text := row_to_json(def_params());
  r_base record;

  t_jsonb CONSTANT text := 'SELECT * FROM jsonb_each(%L::jsonb) ORDER BY key';
  out_text text;
  expected_text text;
BEGIN
  r_base := tf.get(NULL::_classy._class, 'base');
  RETURN NEXT isnt(
    r_base.preprocess_template_id
    , NULL
    , 'preprocess_template_id is not null'
  );

  out_text := trunklet.process( r_base.preprocess_template_id, args );
  expected_text := $$

SELECT json_object( array[
  'function_name', 'classy_test.test_function'
  , 'arguments', 'a int, b int'
  , 'returns', 'int'
  , 'language', NULL
  , 'options', NULL
  , 'body', 'SELECT a+b'
  , 'comment_code', coalesce(
    NULL
    , CASE WHEN nullif('test function', '') IS NOT NULL THEN
        format(
          'COMMENT ON FUNCTION %s(%s) IS %L;'
          , 'classy_test.test_function'
          , 'a int, b int'
          , 'test function'
        )
      END
    , ''
  )
  ] )

$$;
  RETURN NEXT results_eq(
    format($$SELECT unnest(%L::text[])$$, string_to_array(out_text, E'\n'))
    , string_to_array(expected_text, E'\n')
    , 'Preprocess template processes correctly'
  );

  RETURN NEXT results_eq(
    format(
      t_jsonb
      , trunklet.execute_into( r_base.preprocess_template_id, args )
    )
    , format(
      t_jsonb
      , args::jsonb - 'comment' ||
        $${"comment_code" : "COMMENT ON FUNCTION classy_test.test_function(a int, b int) IS 'test function';"}$$::jsonb
    )
    , 'Preprocess template produces correct output'
  );
END
$body$;

CREATE FUNCTION test_instantiate
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
  tf_args CONSTANT text := 'a int, b int';
  tf_argtypes CONSTANT name[] := '{int,int}'::regtype[];

  tf_schema CONSTANT name := '_classy_test';
  tf_name CONSTANT name := 'instantiate_test_function';
  tf_full_name CONSTANT name := tf_schema || '.' || tf_name;
  tf_return CONSTANT name := 'int'::regtype;
  tf_language CONSTANT name := 'sql';

  c_param_jsonb CONSTANT jsonb := params_json(
    tf_full_name
    , tf_args
    , tf_return
    , tf_language
    , body := 'SELECT a+b'
    , comment := 'test function'
  );

  sql text;
BEGIN
  RETURN NEXT tf.tap('_classy._class', 'base');

  RETURN NEXT hasnt_function(
    tf_schema
    , tf_name
    , tf_argtypes
    , 'ensure test function does not already exist'
  );
  sql := format(
    $$SELECT classy.instantiate(%L, 1, %L)$$
    , get_test_class()
    , c_param_jsonb
  );
  RETURN NEXT lives_ok(
    sql
    , sql
  );
  RETURN NEXT throws_ok(
    sql
    , NULL
    , format( 'instance of "%s" already created', get_test_class() )
  );

  RETURN NEXT function_lang_is(
    tf_schema, tf_name, tf_argtypes
    , tf_language
  );

  RETURN NEXT function_returns(
    tf_schema, tf_name, tf_argtypes
    , tf_return
  );

  RETURN NEXT is(
    obj_description( tf_full_name::regproc, 'pg_proc' )
    , 'test function'
    , 'Verify function description'
  );
END
$body$;

-- vi: expandtab sw=2 ts=2
