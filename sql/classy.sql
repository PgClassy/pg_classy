/*
 * Extension is configured to go into the classy schema, which Postgres
 * creates for us. We just need to fix the permissions.
 */
GRANT USAGE ON SCHEMA classy TO public;

CREATE SCHEMA _classy;

CREATE TYPE _classy.class AS (
  class_id        int
  , class_name      text --NOT NULL
  , class_version     int --NOT NULL -- Same as _trunklet.template.template_version
    --CONSTRAINT class_version_must_be_greater_than_0 CHECK( class_version > 0 )
  , unique_parameters_extract_list   text[] --NOT NULL

  -- References to trunklet templates
  , creation_template_id  int --NOT NULL
  , upgrade_template_id   int
    --CONSTRAINT upgrade_template_required_after_version_1 CHECK( class_version = 1 OR upgrade_template_id IS NOT NULL )
  , preprocess_template_id  int
);

CREATE TABLE _classy._class(
  class_id        serial  PRIMARY KEY
  , class_name      text  NOT NULL
  , class_version     int   NOT NULL -- Same as _trunklet.template.template_version
    CONSTRAINT class_version_must_be_greater_than_0 CHECK( class_version > 0 )
  , CONSTRAINT _class__u_class_name__class_version UNIQUE( class_name, class_version )

  , unique_parameters_extract_list   text[] NOT NULL

  -- References to trunklet templates
  , creation_template_id  int NOT NULL
  , upgrade_template_id   int
    CONSTRAINT upgrade_template_required_after_version_1 CHECK( class_version = 1 OR upgrade_template_id IS NOT NULL )
  , preprocess_template_id  int

  -- All other templates will be optional and added as a separate table
);
SELECT trunklet.template__dependency__add( '_classy._class', 'creation_template_id' );
SELECT trunklet.template__dependency__add( '_classy._class', 'upgrade_template_id' );
SELECT trunklet.template__dependency__add( '_classy._class', 'preprocess_template_id' );

-- TTODO: PK, UNIQUE
-- TTODO: types match _trunklet.template fields

/*
CREATE OR REPLACE FUNCTION classy.add(
  class_name text
  , unique_parameters_extract_list text[]
  , creation_template
*/
CREATE OR REPLACE FUNCTION _classy.class__get(
  class_name text
  , class_version int DEFAULT NULL
) RETURNS _classy.class LANGUAGE plpgsql AS $body$
DECLARE
  r_class _classy.class;
BEGIN
  -- Return an error if we don't get a record
  SELECT INTO STRICT r_class
      *
    FROM _classy._class c
    WHERE c.class_name = class__get.class_name
      AND c.class_version = coalesce( class__get.class_version
          , ( SELECT max(c2.class_version) FROM _classy._class c2 WHERE c2.class_name = class__get.class_name )
        )
  ;

  RETURN r_class;
END
$body$;

-- TTODO: error for no record
-- TTODO: properly handle missing class_version
--SELECT variant.register('trunklet_parameters', p_storage_allowed := true);
CREATE TABLE _classy.instance(
  instance_id           serial    PRIMARY KEY
  , class_id            int       NOT NULL REFERENCES _classy._class
  , unique_parameters   text      NOT NULL
  , CONSTRAINT instance__u_class_id__unique_parameters_text UNIQUE( class_id, unique_parameters )
  , parameters          text      NOT NULL
);
-- This can't be a CONSTRAINT due to the cast. Can't use :: syntax because it won't parse.
--CREATE UNIQUE INDEX instance__u_class_id__unique_parameters_text ON _classy.instance( class_id, CAST(unique_parameters AS text) );

CREATE OR REPLACE FUNCTION _classy.instance__get_loose(
  class_id    int
  , unique_parameters   text
) RETURNS _classy.instance LANGUAGE sql AS $body$
  SELECT *
    FROM _classy.instance i
    WHERE i.class_id = class_id
      AND i.unique_parameters::text = unique_parameters::text
$body$;

CREATE OR REPLACE FUNCTION classy.instantiate(
  class_name text
  , class_version int
  , parameters text
) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  r_class _classy.class;
  r_template record;
  r_instance _classy.instance;
  v_unique_parameters text;
  v_parameters text;

  sql text;
BEGIN
-- Note that class definitions might actually be stored in multiple tables
r_class := _classy.class__get(class_name, class_version);

-- TODO: Add formal support for this in trunklet
SELECT INTO STRICT r_template
    *
  FROM _trunklet.template
  WHERE template_id = r_class.creation_template_id
;

/*
 * We may need to pre-process our parameters. NOTE: This needs to happen BEFORE
 * we extract unique parameters.
 */
IF r_class.preprocess_template_id IS NOT NULL THEN
  v_parameters := trunklet.execute_into(
    r_class.preprocess_template_id
    , parameters
  );
ELSE
  v_parameters := parameters;
END IF;

/*
 * Extract parameter values that will uniquely identify this instance of
 * class_name and make sure we haven't already registered them.
 *
 * TODO: We should really track all the objects created by a class. As part of
 * that, we should identify one of those objects as being the 'face' of a
 * class. Maybe a schema, maybe a table, maybe a function.
 */
v_unique_parameters := trunklet.extract_parameters(
  (_trunklet.language__get(r_template.language_id)).language_name
  , v_parameters
  , r_class.unique_parameters_extract_list
);

/*
 * See if we're already instantiated. We don't bother with race condition
 * because our insert at the bottom will eventually fail if nothing else.
 */
r_instance := _classy.instance__get_loose( r_class.class_id, v_unique_parameters );
IF NOT r_instance IS NULL THEN -- Remember that record IS NOT NULL is only true if ALL fields are not null
  RAISE 'instance of % already created', class_name
    USING DETAIL = 'with unique parameters ' || v_unique_parameters::text
  ;
END IF;

  sql := trunklet.process(
    r_template.template_name
    , r_template.template_version
    , v_parameters
  );
  RAISE DEBUG E'executing sql: \n%', sql;
  EXECUTE sql;

  BEGIN
    INSERT INTO _classy.instance(class_id, unique_parameters, parameters)
      VALUES( r_class.class_id, v_unique_parameters, v_parameters )
    ;
  EXCEPTION
    WHEN unique_violation THEN
      RAISE 'instance of "%" already created', class_name
        USING DETAIL = 'with unique parameters ' || v_unique_parameters::text
      ;
  END;
END
$body$;

-- vi: expandtab sw=2 ts=2
