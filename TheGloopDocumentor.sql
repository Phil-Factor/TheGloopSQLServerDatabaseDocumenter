

DECLARE @JSON NVARCHAR(MAX)=(
SELECT Name, Type, Description, [References],[Referenced by], AggregatedObjects AS [contains]
  FROM
    ( --Get the details of the primary objects (no parent objects) e.g. Tables,
    SELECT object.object_id, --needed to find the child objects!
      Object_Schema_Name(object.object_id) + '.' + object.name AS "Name",
      Lower(Replace(object.type_desc, '_', ' ')) + ' (' + RTrim(object.type)
      + ')' AS "Type", -- the type of object
      Convert(NVARCHAR(2000), value) AS "Description", --documentation
	Json_Query(
	  (SELECT '["'+
	    String_Agg(--likely schema name
	    Coalesce(Object_Schema_Name(referencing_id) + '.', '') 
	    + Object_Name(referencing_id)
	    + --definite entity name
	    Coalesce('.' + Col_Name(referencing_id, referencing_minor_id), '') 
			,'", "') +'"]' AS referencing
	  FROM sys.sql_expression_dependencies
      WHERE referenced_id = object.object_id)) as [Referenced by],
	Json_Query(
	 (SELECT '["'+
	    String_Agg(
	    Coalesce(referenced_server_name + '.', '')
	    + --possible server name if cross-server
	    Coalesce(referenced_database_name + '.', '')
	    + --possible database name if cross-database
	    Coalesce(referenced_schema_name + '.', '')
	    + --likely schema name
	    Coalesce(referenced_entity_name, '')
	    + --very likely entity name
	    Coalesce('.' + Col_Name(referenced_id, referenced_minor_id), '') 
	    ,'", "') +'"]' AS referenced
	   FROM sys.sql_expression_dependencies
	   WHERE referencing_id = object.object_id)) AS [References]
     FROM sys.objects AS object --
        LEFT OUTER JOIN sys.extended_properties AS EP
          ON object.object_id = EP.major_id AND class = 1 --objects and columns
         AND minor_id = 0 --base objects only
         AND EP.name = 'MS_Description' --other stuff there
      WHERE is_ms_shipped = 0 AND parent_object_id = 0
    ) AS PrimaryObjects -- this represents all the primary objects
    LEFT OUTER JOIN
      (
      SELECT parent_object_id,
        Json_Query('[' + String_Agg(ChildObjects, ', ') + ']') AS AggregatedObjects
        FROM
          (
          SELECT parent_object_id,
		-- SQL Prompt formatting off
		  '{"' + Type + '":[{"' COLLATE DATABASE_DEFAULT
		  + String_Agg(
			  'Name":"' + String_Escape(Convert(NVARCHAR(MAX), Name),'json') 
			  +' '+ Coalesce(ValueType + ' '  
			  +CASE --do the basic datatype
				WHEN ValueType IN ('char', 'varchar', 'nchar', 'nvarchar')
				THEN '(' + -- we have to put in the length
				  CASE WHEN ValueTypemaxlength = -1 THEN 'MAX'
					ELSE CONVERT(VARCHAR(4),
					  CASE WHEN ValueType IN ('nchar', 'nvarchar')
					  THEN ValueTypemaxlength / 2 ELSE ValueTypemaxlength
					  END)
					END + ')' --having to put in the length
				WHEN ValueType IN ('decimal', 'numeric')
				--Ah. We need to put in the precision
				THEN '(' + CONVERT(VARCHAR(4), ValueTypePrecision)
					  + ',' + CONVERT(VARCHAR(4), ValueTypeScale) + ')'
				ELSE ''-- no more to do
			  END+ --we've now done the datatype
			  CASE WHEN XMLcollectionID <> 0 --when an XML document
				THEN --deal with object schema names
				  '(' +
				  CASE WHEN isXMLDocument = 1 THEN 'DOCUMENT ' ELSE 'CONTENT ' END
				  + COALESCE(
				   QUOTENAME(Schemaename) + '.' + QUOTENAME(SchemaCollectionname)
					,'NULL') + ')'
				  ELSE ''
			  END+'"','"' )--finished doing the name (and datatype if relevant)
			   + Coalesce(',"Description":"' + String_Escape(Description, 'json') + '"', ''),
			  '}, {"') WITHIN GROUP (ORDER BY TheOrder ASC) 
			  --finish off doing the StringAgg
			  + '}]}' COLLATE DATABASE_DEFAULT as ChildObjects

-- SQL Prompt formatting on
            FROM
              (
              SELECT cols.object_id, cols.name AS "Name", 'column' AS "Type",
                cols.max_length AS ValueTypemaxlength,
                cols.precision AS ValueTypePrecision,
                cols.scale AS ValueTypeScale, t.name AS ValueType,
                cols.xml_collection_id AS XMLcollectionID,
                cols.is_xml_document AS isXMLDocument,
                Schemae.name AS Schemaename,
                SchemaCollection.name AS SchemaCollectionName,
                Convert(NVARCHAR(2000), value) AS "Description",
                column_id AS TheOrder
                FROM sys.objects AS object
                  INNER JOIN sys.columns AS cols
                    ON cols.object_id = object.object_id
                  INNER JOIN sys.types AS t
                    ON cols.user_type_id = t.user_type_id
                  LEFT OUTER JOIN sys.xml_schema_collections AS SchemaCollection
                    ON SchemaCollection.xml_collection_id = cols.xml_collection_id
                  LEFT OUTER JOIN sys.schemas AS Schemae
                    ON SchemaCollection.schema_id = Schemae.schema_id
                  LEFT OUTER JOIN sys.extended_properties AS EP
                    ON cols.object_id = EP.major_id
                   AND class = 1
                   AND minor_id = cols.column_id
                   AND EP.name = 'MS_Description'
                WHERE is_ms_shipped = 0
              UNION ALL
              SELECT params.object_id, params.name AS "Name",
                CASE WHEN parameter_id = 0 THEN 'Return' ELSE 'parameter' END AS "Type",
                params.max_length AS ValueTypemaxlength,
                params.precision AS ValueTypePrecision,
                params.scale AS ValueTypeScale, t.name AS ValueType,
                params.xml_collection_id AS XMLcollectionID,
                params.is_xml_document AS isXMLDocument,
                Schemae.name AS Schemaename,
                SchemaCollection.name AS SchemaCollectionName,
                Convert(NVARCHAR(2000), value) AS "Description",
                parameter_id AS TheOrder
                FROM sys.objects AS object
                  INNER JOIN sys.parameters AS params
                    ON params.object_id = object.object_id
                  INNER JOIN sys.types AS t
                    ON params.user_type_id = t.user_type_id
                  LEFT OUTER JOIN sys.xml_schema_collections AS SchemaCollection
                    ON SchemaCollection.xml_collection_id = params.xml_collection_id
                  LEFT OUTER JOIN sys.schemas AS Schemae
                    ON SchemaCollection.schema_id = Schemae.schema_id
                  LEFT OUTER JOIN sys.extended_properties AS EP
                    ON params.object_id = EP.major_id
                   AND class = 2
                   AND minor_id = params.parameter_id
                   AND EP.name = 'MS_Description'
                WHERE is_ms_shipped = 0
              UNION ALL
              --get in all the child objects of the base objects
              SELECT parent_object_id, object.name AS "Name",
                Lower(Replace(object.type_desc, '_', ' ')) + ' ('
                + RTrim(object.type) + ')' AS "Type",
                NULL AS ValueTypemaxlength, NULL AS ValueTypePrecision,
                NULL AS ValueTypeScale, NULL AS ValueType,
                NULL AS XMLcollectionID, NULL AS isXMLDocument,
                NULL AS Schemaename, NULL AS SchemaCollectionName,
                Convert(NVARCHAR(2000), value) AS "Description", 1 AS theorder
                --irrelevant for these child objects
                FROM sys.objects AS object
                  LEFT OUTER JOIN sys.extended_properties AS EP
                    ON object.object_id = EP.major_id
                   AND class = 1
                   AND EP.name = 'MS_Description'
                WHERE is_ms_shipped = 0
              ) AS f(parent_object_id, Name, Type, ValueTypemaxlength, 
			  ValueTypePrecision, ValueTypeScale, ValueType, XMLcollectionID, 
			  isXMLDocument, Schemaename, SchemaCollectionName, Description, TheOrder)
            WHERE parent_object_id > 0
            GROUP BY parent_object_id, Type
          ) AS TheChildObjects
        GROUP BY parent_object_id
      ) AS ArrayOfChildObjects(parent_object_id, AggregatedObjects)
      ON ArrayOfChildObjects.parent_object_id = PrimaryObjects.object_id
FOR JSON PATH)
SELECT @json
