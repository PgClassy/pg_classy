INSERT INTO _classy._class(
    class_name
    , class_version
    , unique_identifier_template_id
    , creation_template_id
    , preprocess_template_id
  ) VALUES(
    'composite_constructor'
    , 1

    , trunklet.template__add(
      'format'
      , 'pg_classy: uniqueness template for "composite_constructor"'
      , $$SELECT array[ 'type', %composite_fqn%L, NULL ]$$
    )

    , trunklet.template__add(
      'format'
      , 'pg_classy: creation template for "composite_constructor"'
      , 
$template$
CREATE OR REPLACE FUNCTION %composite_fqn%s(
%arguments with defaults%s
) RETURNS %composite_fqn%s
LANGUAGE sql IMMUTABLE AS
%body%L
;
COMMENT ON FUNCTION %composite_fqn%s(
%arguments%s
) IS %comment_string%L;
$template$
    )

    , trunklet.template__add(
      'format'
      , 'pg_classy: pre-processing template for "composite_constructor"'
      ,
$template$
WITH atts AS (
  SELECT quote_ident(attname) AS att_name
      , format_type(atttypid, NULL) AS att_type -- typmod shouldn't matter...
    FROM pg_attribute a JOIN pg_type t ON attrelid=typrelid
    WHERE attnum > 0
        AND NOT attisdropped
        -- TODO: validate it's a composite. Cast to regclass to do that doesn't work.
        AND t.oid = %composite%L::regtype
    ORDER BY attnum
)
SELECT row_to_json(final_output, true) FROM (
  SELECT
        composite_fqn
        , '  ' || array_to_string(
            array(SELECT format('%%s %%s', att_name, att_type) FROM atts)
            , E'\n  , '
        ) AS arguments
        , '  ' || array_to_string(
            array(SELECT format('%%s %%s = NULL', att_name, att_type) FROM atts)
            , E'\n  , '
        ) AS "arguments with defaults"
        , format(
            E'SELECT (\n  %%s\n)::%%s'
            , array_to_string(
                array(SELECT att_name FROM atts)
                , E'\n  , '
            )
            , composite_fqn
        ) AS body
        , $$Constructor function for composite type $$ || composite_fqn
          AS comment_string
    FROM (
      SELECT format(
            '%%I.%%s'
            , typnamespace::regnamespace
            , format_type(oid, NULL)
          ) AS composite_fqn
        FROM pg_type
        WHERE oid = %composite%L::regtype
    ) c
) final_output
;
$template$
    )
  )
;

-- vi: expandtab ts=2 sw=2
