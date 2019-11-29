# TheGloopSQLServerDatabaseDocumenter
 the Gloop: SQL Queries that generate JSON Documentation files

## What is the gloop?
This is a way of extracting the ‘documentable’ metadata from a SQL Server database
so you can then  inspect and edit it. This means saving it in JSON format  in a file.
This then will allow you to use whatever JSON editor you prefer. 

I import it into MongoDB. To do the file saving, I use PowerShell. 

You can add documentation and write it into the database

### GloopCollectionOfObjects.sql

This is the version that I used for documenting work. It produces an array of objects, each one representing a base table, view, function etc. The columns, parameters, return values and so on are in a array value for the 'Contains' key.

### GloopWholeDatabase.sql

This presents objects rather more neatly and provides the metadata about the database itself 

### TheGloopDocumentor.sql

This was my original attempt. I like it because it represents columns and parameters in a more compact way, but it can't be used for documenting a database.