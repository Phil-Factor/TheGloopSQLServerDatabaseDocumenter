
CREATE OR ALTER PROCEDURE #ParseJSONMetadataToUpdateTheDocumentation
/**
Summary: >
  This takes a documentation file of a particular JSON format
  and uses it to check if the documnentation is the same in the database
  if it isn't, then it either addes the documentation or amends it
Author: Phil Factor
Date: 29/11/2019
Examples:
   -
      declare @howMany int
	  Execute #ParseJSONMetadataToUpdateTheDocumentation @Json, @HowMany output
	  Select @HowMany
Returns: >
  nothing
**/ 
@JSON nvarchar(MAX),
@NumberChanged int output
AS

DROP TABLE IF EXISTS #TheObjects;
CREATE TABLE #TheObjects
  (
  Name sysname NOT NULL,
  Type NVARCHAR(30) NOT NULL,
  Description NVARCHAR(3750) NULL,
  ParentName sysname NULL,
  [Contains] NVARCHAR(MAX) NULL
  );
INSERT INTO #TheObjects (Name, Type, Description, ParentName, [Contains])
  SELECT BaseObjects.Name, BaseObjects.Type, BaseObjects.Description, NULL,
    [Contains]
    FROM
    OpenJson(@JSON)
    WITH
      (
      Name NVARCHAR(80) '$.Name', Type NVARCHAR(80) '$.Type',
      Parent NVARCHAR(80) '$.Parent',
      Description NVARCHAR(MAX) '$.Description',
      [Contains] NVARCHAR(MAX) '$.contains' AS JSON
      ) AS BaseObjects;

INSERT INTO #TheObjects (Name, Type, Description, ParentName, [Contains])
  SELECT objvalues.Name, obj.[Key] AS Type, objvalues.Description,
    #TheObjects.Name AS ParentName, NULL AS [contains]
    FROM #TheObjects
      OUTER APPLY OpenJson(#TheObjects.[Contains]) AS child
      OUTER APPLY OpenJson(child.Value) AS obj
      OUTER APPLY
    OpenJson(obj.Value)
    WITH (Name NVARCHAR(80) '$.Name', Description NVARCHAR(MAX) '$.Description') AS objvalues;

DROP TABLE IF EXISTS #EPParentObjects;
CREATE TABLE #EPParentObjects
  (
  TheOneToDo INT IDENTITY(1, 1),
  level0_type VARCHAR(128) NULL,
  level0_Name sysname NULL,
  level1_type VARCHAR(128) NULL,
  level1_Name sysname NULL,
  level2_type VARCHAR(128) NULL,
  level2_Name sysname NULL,
  [Description] NVARCHAR(3750),
  );

INSERT INTO #EPParentObjects
  (level0_type, level0_Name, level1_type, level1_Name, level2_type,
level2_Name, Description)
  SELECT 'schema' AS level0_type, ParseName(Name, 2) AS level0_Name,
      CASE WHEN Type LIKE '%FUNCTION%' THEN 'FUNCTION'
        WHEN Type LIKE '%TABLE%' THEN 'TABLE'
        WHEN Type LIKE '%PROCEDURE%' THEN 'PROCEDURE'
        WHEN Type LIKE '%RULE%' THEN 'RULE'
        WHEN Type LIKE '%VIEW%' THEN 'VIEW'
        WHEN Type LIKE '%DEFAULT%' THEN 'DEFAULT'
        WHEN Type LIKE '%AGGREGATE%' THEN 'AGGREGATE'
        WHEN Type LIKE '%LOGICAL FILE NAME%' THEN 'LOGICAL FILE NAME'
        WHEN Type LIKE '%QUEUE%' THEN 'QUEUE'
        WHEN Type LIKE '%RULE%' THEN 'RULE'
        WHEN Type LIKE '%SYNONYM%' THEN 'SYNONYM'
        WHEN Type LIKE '%TYPE%' THEN 'TYPE'
        WHEN Type LIKE '%XML SCHEMA COLLECTION%' THEN 'XML SCHEMA COLLECTION' 
	    ELSE'UNKNOWN' 
	  END AS level1_type,
    ParseName(Name, 1) AS level1_Name, NULL AS level2_type,
    NULL AS level2_Name, Description
    FROM #TheObjects
    WHERE ParentName IS NULL;

INSERT INTO #EPParentObjects
  (level0_type, level0_Name, level1_type, level1_Name, level2_type,
level2_Name, Description)
  SELECT level0_type, level0_Name, level1_type, level1_Name,
      CASE WHEN Type LIKE '%COLUMN%' THEN 'COLUMN'
        WHEN Type LIKE '%CONSTRAINT%' THEN 'CONSTRAINT'
        WHEN Type LIKE '%EVENT NOTIFICATION%' THEN 'EVENT NOTIFICATION'
        WHEN Type LIKE '%INDEX%' THEN 'INDEX'
        WHEN Type LIKE '%PARAMETER%' THEN 'PARAMETER'
        WHEN Type LIKE '%TRIGGER%' THEN 'TRIGGER' 
		ELSE 'UNKNOWN' 
	  END AS Level2_type,
    #TheObjects.Name AS Level2_name, #TheObjects.Description
    FROM #EPParentObjects
      INNER JOIN #TheObjects
        ON level1_Name = ParseName(ParentName, 1) 
		  AND level0_Name =ParseName(ParentName, 2);

--SELECT * FROM #EPParentObjects AS EPO

DECLARE @iiMax int= (SELECT Max(TheOneToDo) FROM #EPParentObjects)
 DECLARE @level0_type VARCHAR(128), @level0_Name sysname,
        @level1_type VARCHAR(128),@level1_Name sysname,
        @level2_type VARCHAR(128),@level2_Name sysname,@Description nvarchar (3750),
        @NeedsChanging BIT,@DidntExist BIT, @Changed INT=0
DECLARE @ii INT =1
WHILE @ii<=@iiMax
    BEGIN
    SELECT @level0_type =level0_type, @level0_Name=level0_Name,
        @level1_type =level1_type,@level1_Name =level1_Name,
        @level2_type=level2_type,@level2_Name =level2_Name,@Description=[description]
        FROM #EPParentObjects WHERE TheOneToDo=@ii
        SELECT @NeedsChanging=CASE WHEN value=@description THEN 0 ELSE 1 end --so what is there existing?
            FROM fn_listextendedproperty ('ms_description',
             @level0_type,@level0_Name,@level1_type,
              @level1_Name,@level2_type,@level2_Name) 
        IF @@RowCount=0 SELECT @DidntExist=1, @NeedsChanging=CASE WHEN @description IS NULL  THEN 0 ELSE 1 END
        IF @NeedsChanging =1
            BEGIN TRY
            SELECT @Changed=@Changed+1
            IF @DidntExist=1
              EXEC sys.sp_addextendedproperty 'ms_description',@description,
                @level0_type,@level0_Name,@level1_type,
                @level1_Name,@level2_type,@level2_Name
			ELSE
              EXEC sys.sp_Updateextendedproperty  'ms_description',@description,
                @level0_type,@level0_Name,@level1_type,
                @level1_Name,@level2_type,@level2_Name 
            END try
			BEGIN CATCH
				DECLARE @theError VARCHAR(2000)=ERROR_MESSAGE()
				RAISERROR ('there was an error ''%s''  called with values ''%s'', ''%s'', ''%s'', ''%s'', ''%s'', ''%s'' with value  ''%s''',16,1,@theError , @level0_type,@level0_Name,@level1_type,
                @level1_Name,@level2_type,@level2_Name,@description)
            END catch
        SELECT @ii=@ii+1
    END
SELECT @NumberChanged= @changed 
GO 

USE customers
DECLARE @JSON NVARCHAR(MAX);
SELECT @JSON = BulkColumn
  FROM
  OpenRowset(BULK 'D:\Data\RawData\customers-ColObs.json', SINGLE_NCLOB)
  AS MyJSONFile;
DECLARE @howManyChanges INT;
EXECUTE #ParseJSONMetadataToUpdateTheDocumentation @JSON, @howManyChanges OUTPUT;
SELECT Convert(VARCHAR(5),@howManyChanges)+ ' descriptions were either changed or added' AS ResultOfUpdate


DECLARE @JSON NVARCHAR(MAX);
SELECT @JSON = BulkColumn
  FROM
  OpenRowset(BULK 'D:\Data\RawData\customers-ColObs.json', SINGLE_NCLOB)
  AS MyJSONFile;

DROP TABLE IF EXISTS #TheObjects;
CREATE TABLE #TheObjects
  (
  Name sysname NOT NULL,
  Type NVARCHAR(30) NOT NULL,
  Description NVARCHAR(3750) NULL,
  ParentName sysname NULL,
  [Contains] NVARCHAR(MAX) NULL
  );

INSERT INTO #TheObjects (Name, Type, Description, ParentName, [Contains])
  SELECT BaseObjects.Name, BaseObjects.Type, BaseObjects.Description, NULL,
    [Contains]
    FROM
    OpenJson(@JSON)
    WITH
      (
      Name NVARCHAR(80) '$.Name', Type NVARCHAR(80) '$.Type',
      Parent NVARCHAR(80) '$.Parent',
      Description NVARCHAR(MAX) '$.Description',
      [Contains] NVARCHAR(MAX) '$.contains' AS JSON
      ) AS BaseObjects;

INSERT INTO #TheObjects (Name, Type, Description, ParentName, [Contains])
  SELECT objvalues.Name, obj.[Key] AS Type, objvalues.Description,
    #TheObjects.Name AS ParentName, NULL AS [contains]
    FROM #TheObjects
      OUTER APPLY OpenJson(#TheObjects.[Contains]) AS child
      OUTER APPLY OpenJson(child.Value) AS obj
      OUTER APPLY
    OpenJson(obj.Value)
    WITH (Name NVARCHAR(80) '$.Name', Description NVARCHAR(MAX) '$.Description') AS objvalues;


DROP TABLE IF EXISTS #EPParentObjects;
CREATE TABLE #EPParentObjects
  (
  TheOneToDo INT IDENTITY(1, 1),
  level0_type VARCHAR(128) NULL,
  level0_Name sysname NULL,
  level1_type VARCHAR(128) NULL,
  level1_Name sysname NULL,
  level2_type VARCHAR(128) NULL,
  level2_Name sysname NULL,
  [Description] NVARCHAR(3750),
  );

INSERT INTO #EPParentObjects
  (level0_type, level0_Name, level1_type, level1_Name, level2_type,
level2_Name, Description)
  SELECT 'schema' AS level0_type, ParseName(Name, 2) AS level0_Name,
      CASE WHEN Type LIKE '%FUNCTION%' THEN 'FUNCTION'
        WHEN Type LIKE '%TABLE%' THEN 'TABLE'
        WHEN Type LIKE '%PROCEDURE%' THEN 'PROCEDURE'
        WHEN Type LIKE '%RULE%' THEN 'RULE'
        WHEN Type LIKE '%VIEW%' THEN 'VIEW'
        WHEN Type LIKE '%DEFAULT%' THEN 'DEFAULT'
        WHEN Type LIKE '%AGGREGATE%' THEN 'AGGREGATE'
        WHEN Type LIKE '%LOGICAL FILE NAME%' THEN 'LOGICAL FILE NAME'
        WHEN Type LIKE '%QUEUE%' THEN 'QUEUE'
        WHEN Type LIKE '%RULE%' THEN 'RULE'
        WHEN Type LIKE '%SYNONYM%' THEN 'SYNONYM'
        WHEN Type LIKE '%TYPE%' THEN 'TYPE'
        WHEN Type LIKE '%XML SCHEMA COLLECTION%' THEN 'XML SCHEMA COLLECTION' 
	    ELSE'UNKNOWN' 
	  END AS level1_type,
    ParseName(Name, 1) AS level1_Name, NULL AS level2_type,
    NULL AS level2_Name, Description
    FROM #TheObjects
    WHERE ParentName IS NULL;

INSERT INTO #EPParentObjects
  (level0_type, level0_Name, level1_type, level1_Name, level2_type,
level2_Name, Description)
  SELECT level0_type, level0_Name, level1_type, level1_Name,
      CASE WHEN Type LIKE '%COLUMN%' THEN 'COLUMN'
        WHEN Type LIKE '%CONSTRAINT%' THEN 'CONSTRAINT'
        WHEN Type LIKE '%EVENT NOTIFICATION%' THEN 'EVENT NOTIFICATION'
        WHEN Type LIKE '%INDEX%' THEN 'INDEX'
        WHEN Type LIKE '%PARAMETER%' THEN 'PARAMETER'
        WHEN Type LIKE '%TRIGGER%' THEN 'TRIGGER' 
		ELSE 'UNKNOWN' 
	  END AS Level2_type,
    #TheObjects.Name AS Level2_name, #TheObjects.Description
    FROM #EPParentObjects
      INNER JOIN #TheObjects
        ON level1_Name = ParseName(ParentName, 1) 
		  AND level0_Name =ParseName(ParentName, 2);

SELECT * FROM #EPParentObjects AS EPO




