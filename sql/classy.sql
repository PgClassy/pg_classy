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

  -- References to trunklet templates
  , unique_identifier_template_id int --NOT NULL
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

  -- References to trunklet templates
  , unique_identifier_template_id int NOT NULL
  , creation_template_id  int NOT NULL
  , upgrade_template_id   int
    CONSTRAINT upgrade_template_required_after_version_1 CHECK( class_version = 1 OR upgrade_template_id IS NOT NULL )
  , preprocess_template_id  int

  -- All other templates will be optional and added as a separate table
);
SELECT trunklet.template__dependency__add( '_classy._class', 'unique_identifier_template_id' );
SELECT trunklet.template__dependency__add( '_classy._class', 'creation_template_id' );
SELECT trunklet.template__dependency__add( '_classy._class', 'upgrade_template_id' );
SELECT trunklet.template__dependency__add( '_classy._class', 'preprocess_template_id' );

-- TTODO: PK, UNIQUE
-- TTODO: types match _trunklet.template fields

/*
CREATE OR REPLACE FUNCTION classy.add(
  class_name text
  , ...
*/
CREATE OR REPLACE FUNCTION _classy.class__get_loose(
  class_name text
  , class_version int DEFAULT NULL
) RETURNS _classy.class LANGUAGE sql AS $body$
SELECT *
  FROM _classy._class c
  WHERE c.class_name = class__get_loose.class_name
    AND c.class_version = coalesce(
        class__get_loose.class_version
        , ( SELECT max(c2.class_version)
              FROM _classy._class c2
              WHERE c2.class_name = class__get_loose.class_name
          )
      )
$body$;

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
    FROM _classy.class__get_loose(class_name, class_version)
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
  , object_group_id     int       NOT NULL -- Will reference _object_reference.object_group
  , unique_object_id    int       NOT NULL
  , CONSTRAINT instance__u_class_id__unique_parameters_text UNIQUE( class_id, unique_object_id )
  , sql                 text      NOT NULL -- Likely to be toasted, so might as well stick it here
  , raw_parameters      text      NOT NULL
  , processed_parameters    text
);
SELECT object_reference.object_group__dependency__add('_classy.instance', 'object_group_id');
SELECT object_reference.object__dependency__add('_classy.instance', 'unique_object_id');

CREATE OR REPLACE FUNCTION _classy.instance__get_loose(
  class_id    int
  , unique_object_id int
) RETURNS _classy.instance LANGUAGE sql AS $body$
  SELECT *
    FROM _classy.instance i
    WHERE i.class_id = instance__get_loose.class_id
      AND i.unique_object_id = instance__get_loose.unique_object_id
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
  r_instance2 _classy.instance;

  v_parameters text;
  a_unique_parameters text[3];

BEGIN
-- Note that class definitions might actually be stored in multiple tables
r_class := _classy.class__get(class_name, class_version);
r_instance.class_id = r_class.class_id;

-- TODO: Add formal support for this in trunklet
SELECT INTO STRICT r_template
    *
  FROM _trunklet.template
  WHERE template_id = r_class.creation_template_id
;

/*
 * We may need to pre-process our parameters. NOTE: This needs to happen BEFORE
 * we get our unique identifier
 */
r_instance.raw_parameters := parameters;
IF r_class.preprocess_template_id IS NOT NULL THEN
  v_parameters := trunklet.execute_into(
    r_class.preprocess_template_id
    , parameters
  );
  r_instance.processed_parameters := v_parameters;
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
a_unique_parameters := trunklet.execute_text(
  r_class.unique_identifier_template_id
  , v_parameters
);
IF array_dims(a_unique_parameters) <> '[1:3]' THEN
  RAISE 'unique parameter template must return a 1 dimension array with 3 elements'
    USING DETAIL = format( 'template returned %L', a_unique_parameters )
  ;
END IF;
r_instance.unique_object_id := object_reference.object__getsert(
  a_unique_parameters[1]
  , a_unique_parameters[2]
  , a_unique_parameters[3]
  , loose := true -- Don't want this to throw an error if the object doesn't exist
);

/*
 * See if we're already instantiated. We don't bother with race condition
 * because our insert at the bottom will eventually fail if nothing else.
 */
r_instance2 := _classy.instance__get_loose( r_class.class_id, r_instance.unique_object_id );
IF NOT r_instance2 IS NULL THEN -- Remember that record IS NOT NULL is only true if ALL fields are not null
  RAISE DEBUG 'r_instance = %', r_instance;
  RAISE 'instance of % already created', class_name
    USING DETAIL = 'with unique parameters ' || a_unique_parameters::text
  ;
END IF;

  /*
   * Create object_reference group for this instance.
   */
  r_instance.instance_id := cat_tools.sequence__next('_classy.instance', 'instance_id');
  r_instance.object_group_id := object_reference.object_group__create(
    format(
      'classy: class %s (id %s), instance_id %s (unique parameters %s)'
      , r_class.class_name
      , r_class.class_id
      , r_instance.instance_id
      , a_unique_parameters
    )
  );

  r_instance.sql := trunklet.process(
    r_template.template_name
    , r_template.template_version
    , v_parameters
  );
  RAISE DEBUG E'executing sql: \n%', r_instance.sql;

  -- Keep the capture as close as possible to the actual creation
  PERFORM object_reference.capture__start(r_instance.object_group_id);
  EXECUTE r_instance.sql;
  PERFORM object_reference.capture__stop(r_instance.object_group_id);

  -- unique object better exist by now
  r_instance.unique_object_id := object_reference.object__getsert(
    a_unique_parameters[1]
    , a_unique_parameters[2]
    , a_unique_parameters[3]
    , loose := true -- Don't want this to throw an error if the object doesn't exist
  );

  DECLARE
    con_name text;
  BEGIN
    INSERT INTO _classy.instance VALUES( r_instance.* );
  EXCEPTION
    WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS con_name = CONSTRAINT_NAME;
      IF con_name = 'instance__u_class_id__unique_parameters_text' THEN
        RAISE 'instance of "%" already created', class_name
          USING DETAIL = 'with unique parameters ' || a_unique_parameters::text
        ;
      ELSE
        RAISE;
      END IF;
  END;
END
$body$;

CREATE OR REPLACE FUNCTION _classy.class__add(
  class_name text
  , template_language text
  , unique_identifier_template text
  , creation_template text
  , upgrade_template text DEFAULT NULL
  , preprocess_template text DEFAULT NULL
) RETURNS int LANGUAGE plpgsql AS $body$
DECLARE
  c_version CONSTANT int := CASE
    WHEN upgrade_template IS NULL THEN 1
    -- Will throw an error if class doesn't exist, which is what we want
    ELSE (_classy.class__get(class_name)).class_version
  END;

  v_class_id int;
BEGIN
  INSERT INTO _classy._class( class_name, class_version
    , unique_identifier_template_id
    , creation_template_id
    , upgrade_template_id
    , preprocess_template_id
  ) VALUES (
    class_name, c_version

    , trunklet.template__add(
      template_language
      , format('pg_classy: unique identifier template for "%s"', class_name)
      , c_version
      , unique_identifier_template
    )
    
    , trunklet.template__add(
      template_language
      , format('pg_classy: creation template for "%s"', class_name)
      , c_version
      , creation_template
    )
    
    , CASE WHEN upgrade_template IS NOT NULL THEN
      trunklet.template__add(
        template_language
        , format('pg_classy: upgrade template for "%s"', class_name)
        , c_version
        , upgrade_template
      )
    END
    
    , CASE WHEN preprocess_template IS NOT NULL THEN
      trunklet.template__add(
        template_language
        , format('pg_classy: pre-process template for "%s"', class_name)
        , c_version
        , preprocess_template
      )
    END
  )
    RETURNING class_id INTO STRICT v_class_id
  ;
    
  RETURN v_class_id;
END
$body$;

CREATE OR REPLACE FUNCTION classy.class__create(
  class_name text
  , template_language text
  , unique_identifier_template text
  , creation_template text
  , preprocess_template text DEFAULT NULL
) RETURNS int LANGUAGE sql SECURITY DEFINER AS $body$
SELECT _classy.class__add(
  class_name
  , template_language
  , unique_identifier_template
  , creation_template
  , NULL
  , preprocess_template
)
$body$;

CREATE OR REPLACE FUNCTION classy.class__upgrade(
  class_name text
  , template_language text
  , unique_identifier_template text
  , creation_template text
  , upgrade_template text
  , preprocess_template text DEFAULT NULL
) RETURNS int LANGUAGE sql SECURITY DEFINER AS $body$
SELECT _classy.class__add(
  class_name
  , template_language
  , unique_identifier_template
  , creation_template
  , upgrade_template
  , preprocess_template
)
$body$;

-- vi: expandtab sw=2 ts=2
