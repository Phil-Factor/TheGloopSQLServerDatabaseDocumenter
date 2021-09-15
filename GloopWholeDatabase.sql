SET NOCOUNT ON
DECLARE @TheJSON NVARCHAR(MAX)
SELECT @TheJSON=(
SELECT Db_name() AS name,  Json_Query((SELECT name, value FROM sys.extended_properties AS EP2 WHERE EP2.class_desc='Database'FOR JSON auto)) AS properties, Json_Query('['+String_Agg(attributes,',')+']')AS [objects] FROM 
--SELECT Db_name() AS name, isjson(attributes) FROM 
(
SELECT ('{"'+Type + '": [ {' 
						  + String_Agg('"'+Convert(NVARCHAR(MAX), [Name]) + '": {'
						  --some others that may or may not be there
                          + Coalesce(Stuff(Coalesce(',"Description":"' +[Description]+ '"', '')
                          + Coalesce(',"References":' +[References], '')
                          + Coalesce(',"Referenced by":' +[Referenced by], '')
                          + Coalesce(','+aggregatedObjects, ''),1,1,''),''),
                          '}}, {') +'}}]}')AS attributes
   FROM
    (--Get the details of the primary objects (no parent objects) e.g. Tables,
    SELECT object.object_id,--needed to find the child objects!
      String_Escape(Object_Schema_Name(object.object_id) + '.' + object.name,'json') AS "Name",
      Lower(Replace(object.type_desc, '_', ' ')) + ' (' + RTrim(object.type)
      + ')' AS "Type",-- the type of object
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
				,'", "')  +'"]' AS referenced
			   FROM sys.sql_expression_dependencies
			   WHERE referencing_id = object.object_id)) AS [References],
		String_Escape(Convert(NVARCHAR(2000), value),'json') AS "Description"--documentation
		FROM sys.objects AS object --
		LEFT OUTER JOIN sys.extended_properties AS EP
			ON object.object_id = EP.major_id
			AND class = 1 --objects and columns
			AND minor_id = 0 --base objects only
			AND EP.name = 'MS_Description' --other stuff there
		WHERE is_ms_shipped = 0 AND parent_object_id = 0
     ) AS PrimaryObjects -- this represents all the primary objects
    LEFT OUTER JOIN
      (
      SELECT parent_object_id,
        '' + String_Agg(ChildObjects, ', ') + '' AS AggregatedObjects
        FROM
          (
          SELECT parent_object_id,
              '"' + Type + '":[{"' COLLATE DATABASE_DEFAULT
              + String_Agg(
                          'Name":"' + Convert(NVARCHAR(MAX), Name) + '" '
                          + Coalesce(',"Description":"' + Description + '"', '')
						  + Coalesce(',"Datatype":"' + Datatype + '"', '')
						  ,
                          '}, {"'
                        )WITHIN GROUP ( ORDER BY theorder ASC )    
			  + '}]' COLLATE DATABASE_DEFAULT AS ChildObjects
			FROM
				(
				--get in all the child objects of the base objects
				SELECT parent_object_id,
					String_Escape(object.name, 'json') AS "Name",
					Lower(Replace(object.type_desc, '_', ' ')) + ' ('
					+ RTrim(object.type) + ')' AS "Type",
					String_Escape(Convert(NVARCHAR(2000), value), 'json') AS "Description",
					1 AS theorder, NULL AS datatype
					--irrelevant for these child objects
					FROM sys.objects AS object
					LEFT OUTER JOIN sys.extended_properties AS EP
						ON object.object_id = EP.major_id
						AND class = 1
						AND EP.name = 'MS_Description' -- AND minor_id<>0 
					WHERE is_ms_shipped = 0
				UNION ALL --the indexes
				SELECT object.object_id,
					String_Escape(object.name, 'json') AS "Name",
					'Index' AS "Type",
					String_Escape(Convert(NVARCHAR(2000), value), 'json') AS "Description",
					index_id AS theorder, NULL AS datatype
					FROM sys.objects AS object
					INNER JOIN sys.indexes AS ix
						ON ix.object_id = object.object_id
						AND is_ms_shipped = 0
						AND is_primary_key = 0
						AND is_unique_constraint = 0
						AND index_id > 0 --no heaps please
					LEFT OUTER JOIN sys.extended_properties AS EP
						ON ix.object_id = EP.major_id
						AND class = 7
						AND minor_id = ix.index_id
						AND EP.name = 'MS_Description'
				UNION ALL
				SELECT object_id, colsandparams.Name, Type,
					Description, TheOrder,
		-- SQL Prompt formatting off
					t.[name]+ CASE --do the basic datatype
					WHEN t.[name] IN ('char', 'varchar', 'nchar', 'nvarchar')
					THEN '(' + -- we have to put in the length
						CASE WHEN ValueTypemaxlength = -1 THEN 'MAX'
						ELSE CONVERT(VARCHAR(4),
							CASE WHEN t.[name] IN ('nchar', 'nvarchar')
							THEN ValueTypemaxlength / 2 ELSE ValueTypemaxlength
							END)
						END + ')' --having to put in the length
					WHEN t.[name] IN ('decimal', 'numeric')
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
						QUOTENAME(Schemae.name) + '.' + QUOTENAME(SchemaCollection.name)
						,'NULL') + ')'
						ELSE ''
					END    AS DataType
		-- SQL Prompt formatting on
					FROM
					(
					SELECT cols.object_id,
						String_Escape(cols.name, 'json') AS "Name",
						'column' AS "Type",
						String_Escape(Convert(NVARCHAR(2000), value), 'json'
		)                             AS "Description", column_id AS TheOrder,
						cols.xml_collection_id,
						cols.max_length AS ValueTypemaxlength,
						cols.precision AS ValueTypePrecision,
						cols.scale AS ValueTypeScale,
						cols.xml_collection_id AS XMLcollectionID,
						cols.is_xml_document AS isXMLDocument,
						cols.user_type_id
						FROM sys.objects AS object
						INNER JOIN sys.columns AS cols
							ON cols.object_id = object.object_id
						LEFT OUTER JOIN sys.extended_properties AS EP
							ON cols.object_id = EP.major_id
							AND class = 1
							AND minor_id = cols.column_id
							AND EP.name = 'MS_Description'
						WHERE is_ms_shipped = 0
					UNION ALL
					--get in all the parameters
					SELECT params.object_id, params.name AS "Name",
						CASE WHEN parameter_id = 0 THEN 'Return' ELSE 'parameter' END AS "Type",
						String_Escape( Convert(NVARCHAR(2000), value), 'json'
		)                             AS "Description", parameter_id AS TheOrder,
						params.xml_collection_id,
						params.max_length AS ValueTypemaxlength,
						params.precision AS ValueTypePrecision,
						params.scale AS ValueTypeScale,
						params.xml_collection_id AS XMLcollectionID,
						params.is_xml_document AS isXMLDocument,
						params.user_type_id
						FROM sys.objects AS object
						INNER JOIN sys.parameters AS params
							ON params.object_id = object.object_id
						LEFT OUTER JOIN sys.extended_properties AS EP
							ON params.object_id = EP.major_id
							AND class = 2
							AND minor_id = params.parameter_id
							AND EP.name = 'MS_Description'
						WHERE is_ms_shipped = 0
					) AS colsandparams
					INNER JOIN sys.types AS t
						ON colsandparams.user_type_id = t.user_type_id
					LEFT OUTER JOIN sys.xml_schema_collections AS SchemaCollection
						ON SchemaCollection.xml_collection_id = colsandparams.xml_collection_id
					LEFT OUTER JOIN sys.schemas AS Schemae
						ON SchemaCollection.schema_id = Schemae.schema_id
				) AS f(parent_object_id, Name, Type, Description, TheOrder, Datatype)
				WHERE parent_object_id > 0
				GROUP BY parent_object_id, Type
			) AS ChildObjects
		 GROUP BY parent_object_id
      ) AS ArrayOfChildObjects(parent_object_id, AggregatedObjects)
      ON ArrayOfChildObjects.parent_object_id = PrimaryObjects.object_id
GROUP BY type
)ObjectsAndAttributes
FOR JSON AUTO
)
SELECT @TheJSON AS theJSON
