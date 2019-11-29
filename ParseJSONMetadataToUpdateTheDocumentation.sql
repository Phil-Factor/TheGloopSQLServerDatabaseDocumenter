
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
DECLARE @JSON NVARCHAR(MAX) ='[
{ 
    
    "Name" : "Customer.EmailAddress", 
    "Type" : "user table (U)", 
	"Description" : "Contains the Email addresses. One person can have none or several email addresses",
    "contains" : [
        {
            "column" : [
                {
                    "Name" : "EmailAddress", 
                    "Description" : "the email address"
                }, 
                {
                    "Name" : "EmailID", 
                    "Description" : "the surrogate key for the email address"
                }, 
                {
                    "Name" : "EndDate", 
                    "Description" : "when the email stopped being valid"
                }, 
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "when the email record was last modified"
                }, 
                {
                    "Name" : "Person_id", 
                    "Description" : "the person associated with the email address"
                }, 
                {
                    "Name" : "StartDate", 
                    "Description" : "the time when we created the record"
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "EmailAddressModifiedDateD",
					"Description" : "unless otherwise, make it the date the record was created"
                }
            ]
        }, 
        {
            "foreign key constraint (F)" : [
                {
                    "Name" : "EmailAddress_PersonFK",
					"Description" : "relates to the person with the email address"
                }
            ]
        }, 
        {
            "Index" : [
                {
                    "Name" : "EmailAddress",
					"Description" : "Deal with searches on the email address for the owner"
                }
            ]
        }
    ]
},
{ 
    
    "Name" : "Customer.Person", 
    "Type" : "user table (U)", 
    "Description" : "People involved with the Widget Manufacturing Co.", 
    "contains" : [
        {
            "column" : [
                {
                    "Name" : "FirstName", 
                    "Description" : "First name of the person."
                }, 
                {
                    "Name" : "fullName"
                }, 
                {
                    "Name" : "LastName", 
                    "Description" : "Last name of the person."
                }, 
                {
                    "Name" : "MiddleName", 
                    "Description" : "Middle name or middle initial of the person."
                }, 
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "Date and time the record was last updated."
                }, 
                {
                    "Name" : "person_ID", 
                    "Description" : "Primary key for Person records."
                }, 
                {
                    "Name" : "Suffix", 
                    "Description" : "Surname suffix. For example, Sr. or Jr."
                }, 
                {
                    "Name" : "Title", 
                    "Description" : "A courtesy title. For example, Mr. or Ms."
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "PersonModifiedDateD",
					"Description" : "Default this to the date the record was created"
                }
            ]
        }, 
        {
            "Index" : [
                {
                    "Name" : "Person"
                }
            ]
        }, 
        {
            "primary key constraint (PK)" : [
                {
                    "Name" : "PersonIDPK",
					"Description" : "the key field for the table"
                }
            ]
        }
    ]
},
{ 
    
    "Name" : "Customer.Address", 
    "Type" : "user table (U)", 
    "Description" : "Street address information for CustomersCopy, employees, and vendors.", 
    "contains" : [
        {
            "check constraint (C)" : [
                {
                    "Name" : "Address_Not_Complete"
                }
            ]
        }, 
        {
            "column" : [
                {
                    "Name" : "Address_ID", 
                    "Description" : "Primary key for Address records."
                }, 
                {
                    "Name" : "AddressLine1", 
                    "Description" : "First street address line."
                }, 
                {
                    "Name" : "AddressLine2", 
                    "Description" : "Second street address line."
                }, 
                {
                    "Name" : "City", 
                    "Description" : "Name of the city."
                }, 
                {
                    "Name" : "County", 
                    "Description" : "the county associated with the address"
                }, 
                {
                    "Name" : "Full_Address"
                }, 
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "Date and time the record was last updated."
                }, 
                {
                    "Name" : "PostCode", 
                    "Description" : "Postal code for the street address."
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "DF__Address__Modifie__625A9A57"
                }
            ]
        }, 
        {
            "primary key constraint (PK)" : [
                {
                    "Name" : "AddressPK"
                }
            ]
        }
    ]
},
{ 
    
    "Name" : "Customer.AddressType", 
    "Type" : "user table (U)", 
    "contains" : [
        {
            "column" : [
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "When the type of address was first defined"
                }, 
                {
                    "Name" : "TypeOfAddress", 
                    "Description" : "a string describing a type of address"
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "AddressTypeModifiedDateD"
                }
            ]
        }, 
        {
            "primary key constraint (PK)" : [
                {
                    "Name" : "TypeOfAddressPK"
                }
            ]
        }
    ]
},
{ 
    
    "Name" : "Customer.Abode", 
    "Type" : "user table (U)", 
    "contains" : [
        {
            "column" : [
                {
                    "Name" : "Abode_ID", 
                    "Description" : "the surrogate key for an abode"
                }, 
                {
                    "Name" : "Address_id", 
                    "Description" : "the address concerned"
                }, 
                {
                    "Name" : "End_date", 
                    "Description" : "when the address stopped being associated with the customer"
                }, 
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "when this record was last modified"
                }, 
                {
                    "Name" : "Person_id", 
                    "Description" : "the person associated with the address"
                }, 
                {
                    "Name" : "Start_date", 
                    "Description" : "when the person started being associated with the address"
                }, 
                {
                    "Name" : "TypeOfAddress", 
                    "Description" : "the type of address"
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "AbodeModifiedD"
                }
            ]
        }, 
        {
            "foreign key constraint (F)" : [
                {
                    "Name" : "Abode_PersonFK"
                }, 
                {
                    "Name" : "Abode_AddressFK"
                }, 
                {
                    "Name" : "Abode_AddressTypeFK"
                }
            ]
        }, 
        {
            "primary key constraint (PK)" : [
                {
                    "Name" : "AbodePK"
                }
            ]
        }
    ]
},
{ 
    
    "Name" : "Customer.PhoneType", 
    "Type" : "user table (U)", 
    "contains" : [
        {
            "column" : [
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "when the definition of the type of phone was last modified"
                }, 
                {
                    "Name" : "TypeOfPhone", 
                    "Description" : "a description of the type of phone (e.g. Mobile, work, home)"
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "PhoneTypeModifiedDateD"
                }
            ]
        }, 
        {
            "primary key constraint (PK)" : [
                {
                    "Name" : "PhoneTypePK"
                }
            ]
        }
    ]
},
{ 
    
    "Name" : "Customer.Phone", 
    "Type" : "user table (U)", 
    "contains" : [
        {
            "column" : [
                {
                    "Name" : "DiallingNumber", 
                    "Description" : "the actual number to dial"
                }, 
                {
                    "Name" : "End_date", 
                    "Description" : "When the phone number stopped being associated with the person"
                }, 
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "when the phone record was last modified"
                }, 
                {
                    "Name" : "Person_id", 
                    "Description" : "the person associated with the phone"
                }, 
                {
                    "Name" : "Phone_ID", 
                    "Description" : "surrogate key for the record of the phone association"
                }, 
                {
                    "Name" : "Start_date", 
                    "Description" : "when the customer started being associated with the phone"
                }, 
                {
                    "Name" : "TypeOfPhone", 
                    "Description" : "the type of phone, defined in a separate table"
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "PhoneModifiedDateD"
                }
            ]
        }, 
        {
            "foreign key constraint (F)" : [
                {
                    "Name" : "Phone_PersonFK"
                }, 
                {
                    "Name" : "FK__Phone__TypeOfPho__72910220"
                }
            ]
        }, 
        {
            "primary key constraint (PK)" : [
                {
                    "Name" : "PhonePK"
                }
            ]
        }
    ]
},
{ 
    
    "Name" : "Customer.Note", 
    "Type" : "user table (U)", 
    "contains" : [
        {
            "column" : [
                {
                    "Name" : "InsertionDate", 
                    "Description" : "when the note was recorded in the database"
                }, 
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "when the note was last modified"
                }, 
                {
                    "Name" : "Note", 
                    "Description" : "record of a communication from the person"
                }, 
                {
                    "Name" : "Note_id", 
                    "Description" : "the surrogate key for the note"
                }, 
                {
                    "Name" : "NoteStart"
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "NoteInsertionDateDL"
                }, 
                {
                    "Name" : "NoteModifiedDateD"
                }
            ]
        }, 
        {
            "primary key constraint (PK)" : [
                {
                    "Name" : "NotePK"
                }
            ]
        }, 
        {
            "unique constraint (UQ)" : [
                {
                    "Name" : "NoteStartUQ"
                }
            ]
        }
    ]
},
{ 
    
    "Name" : "Customer.NotePerson", 
    "Type" : "user table (U)", 
    "contains" : [
        {
            "column" : [
                {
                    "Name" : "InsertionDate", 
                    "Description" : "when the association between customer and note was inserted"
                }, 
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "when the association between customer and note note was last modified"
                }, 
                {
                    "Name" : "Note_id", 
                    "Description" : "the note that is associated with the customer"
                }, 
                {
                    "Name" : "NotePerson_id", 
                    "Description" : "the surrogate key for the association between customer and note"
                }, 
                {
                    "Name" : "Person_id", 
                    "Description" : "the person who is associated with the note"
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "NotePersonInsertionDateD"
                }, 
                {
                    "Name" : "NotePersonModifiedDateD"
                }
            ]
        }, 
        {
            "foreign key constraint (F)" : [
                {
                    "Name" : "NotePerson_PersonFK"
                }, 
                {
                    "Name" : "NotePerson_NoteFK"
                }
            ]
        }, 
        {
            "primary key constraint (PK)" : [
                {
                    "Name" : "NotePersonPK"
                }
            ]
        }, 
        {
            "unique constraint (UQ)" : [
                {
                    "Name" : "DuplicateUK"
                }
            ]
        }
    ]
},
{ 
    
    "Name" : "Customer.CreditCard", 
    "Type" : "user table (U)", 
    "contains" : [
        {
            "column" : [
                {
                    "Name" : "CardNumber", 
                    "Description" : "the credit card number"
                }, 
                {
                    "Name" : "CreditCardID", 
                    "Description" : "the surrogate key for the credit card"
                }, 
                {
                    "Name" : "CVC", 
                    "Description" : "the number on the back of the card"
                }, 
                {
                    "Name" : "ModifiedDate", 
                    "Description" : "when this record was last modified"
                }, 
                {
                    "Name" : "Person_id", 
                    "Description" : "the person owning the credit card"
                }, 
                {
                    "Name" : "ValidFrom", 
                    "Description" : "the date from when the card is valid"
                }, 
                {
                    "Name" : "ValidTo", 
                    "Description" : "the date to which the card remains valid"
                }
            ]
        }, 
        {
            "default constraint (D)" : [
                {
                    "Name" : "CreditCardModifiedDateD"
                }
            ]
        }, 
        {
            "foreign key constraint (F)" : [
                {
                    "Name" : "CreditCard_PersonFK"
                }
            ]
        }, 
        {
            "primary key constraint (PK)" : [
                {
                    "Name" : "CreditCardPK"
                }
            ]
        }, 
        {
            "unique constraint (UQ)" : [
                {
                    "Name" : "DuplicateCreditCardUK"
                }
            ]
        }
    ]
}
]
'
      declare @howMany int
	  Execute #ParseJSONMetadataToUpdateTheDocumentation @Json, @HowMany output
	  Select @HowMany
