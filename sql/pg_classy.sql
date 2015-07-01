/*
 * Extension is configured to go into the pg_classy schema, which Postgres
 * creates for us. We just need to fix the permissions.
 */
GRANT USAGE ON SCHEMA pg_classy TO public;

CREATE SCHEMA _pg_classy;

CREATE TYPE _pg_classy.class AS (
  class_id        int
  , class_name      text
  , class_version     int -- Same as _trunklet.template.template_version
  , unique_parameters   variant(trunklet_parameter)

  -- Denormalized from _trunklet.template.template_name
  , preprocess_template_name  text
  , creation_template_name  text
  , test_template_name    text
);

CREATE TABLE _pg_classy._class(
  class_id        serial  PRIMARY KEY
  , class_name      text  NOT NULL
  , class_version     int   NOT NULL -- Same as _trunklet.template.template_version
  , unique_parameters   variant(trunklet_parameter) NOT NULL

  -- Denormalized from _trunklet.template.template_name
  , preprocess_template_name  text
  , creation_template_name  text
  , test_template_name    text
  , CONSTRAINT _class__u_class_name__class_version UNIQUE( class_name, class_version )
);

-- TTODO: PK, UNIQUE
-- TTODO: types match _trunklet.template fields

CREATE OR REPLACE FUNCTION _pg_classy.class__get(
  class_name text
  , class_version int DEFAULT NULL
) RETURNS _pg_classy.class LANGUAGE plpgsql AS $body$
DECLARE
  r_class _pg_classy.class;
BEGIN
  -- Return an error if we don't get a record
  SELECT STRICT INTO r_class
      *
    FROM _pg_classy._class c
    WHERE c.class_name = class_name
      AND c.class_version = coalesce( class_version
          , ( SELECT max(class_version) FROM _pg_classy._class WHERE class_name = class_name )
        )
  ;

  RETURN r_class;
END
$body$;

-- TTODO: error for no record
-- TTODO: properly handle missing class_version

CREATE TABLE _pg_classy.instantiated(
  instance_id           serial    PRIMARY KEY
  , class_id            int       NOT NULL REFERENCES _pg_classy.class
  -- Uhoh... variant currently doesn't support indexes
  , unique_parameters   variant(trunklet_parameters)  NOT NULL UNIQUE
);

CREATE OR REPLACE FUNCTION _pg_classy.instantiated__get_loose(
  class_id    int
  , unique_parameters variant(trunklet_parameters)
) RETURNS _pg_classy.instantiated LANGUAGE sql AS $body$
  SELECT *
    FROM _pg_classy.instantiated i
    WHERE i.class_id = class_id
      AND i.unique_parameters = unique_parameters
$body$;

CREATE OR REPLACE FUNCTION pg_classy.instantiate(
  class_name text
  , class_version int
  , parameters variant
) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  r_class _pg_classy.class;
  r_instantiated record;
  v_parameters variant := paramaters;
  v_unique_parameters variant;
BEGIN
-- Note that class definitions might actually be stored in multiple tables
r_class := _pg_classy.class__get(class_name, class_version);

/*
 * Extract parameter values that will uniquely identify this instance of
 * class_name and make sure we haven't already registered them.
 */
v_unique_parameters := extract_parameters(r_class.unique_parameters, parameters);

/*
 * See if we're already instantiated. We don't bother with race condition
 * because our insert at the bottom will eventually fail if nothing else.
 */
r_instantiated := _pg_classy.instantiated__get( r_class.class_id, v_unique_paramaters );
IF true or FOUND THEN
  BEGIN
    RAISE 'test %', '(1,1)'::point::int; -- Test error handling
    RAISE 'class % already instantiated', class_name
      , USING DETAIL = 'with parameters ' || v_unique_parameters::text
    ;
  EXCEPTION
    RAISE '%',  SQLSTATE;
  END;
END IF;

/*
 * We may need to pre-process our parameters.
 */

IF r_class.preprocess_template_name IS NOT NULL THEN
  v_paramaters := trunklet.execute_into(
    r_class.preprocess_template_name
    , class_version
    , creation_preprocess\[i], parameters
  );
END IF;

PERFORM execute(
  r_class.creation_template_name
  , class_version
  , v_parameters
);

  BEGIN
    INSERT INTO _pg_classy.instances(class_id, class_version, unique_parameters, final_parameters)
      VALUES( r_class.class_id, r_class.version, v_unique_parameters, v_paramaters )
    ;
  EXCEPTION
    WHEN unique_violation THEN
      RAISE EXCEPTION 'class % identified by % already instantiated',
        class_name, v_unique_paramaters
      ;
  END;
END
$body$;

-- vi: expandtab sw=2 ts=2
