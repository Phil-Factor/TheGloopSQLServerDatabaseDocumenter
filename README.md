# The Gloop: SQL Server Database Documenter
 The Gloop: SQL Queries for SQL Server that generate JSON Documentation files and allow you to compare databases sufficiently to provide a narrative of changes. It is called The Gloop because that was what one critical person called it when he saw the code.  The code is contorted because it is trying to generate JSON Files and several database objects such as columns, returned values and parameters require the same rather complicated processing. 

## What is the gloop?
This is a way of extracting the ‘documentable’ metadata from a SQL Server database
so you can then  inspect, compare it and edit it. This means saving it in JSON format  in a file.
This then will allow you to use whatever JSON editor you prefer to edit it. 

I edit it with JSONBuddy, import it into MongoDB. To do the file saving, I use PowerShell. 

Some of the routines allow you to add documentation and write it into the database

The **GloopDatabaseModel** Query is used together with PowerShell to tell you what’s changed between databases. If you use the Get-ODBCSourceMetadata powershell cmdlet, you can compare any ODBC database to find the differences. Beware, because it only does this at a high level of tavles/functions/indexes and so on.

### GloopCollectionOfObjects.sql

This is the version that I used for documenting work. It produces an array of objects, each one representing a base table, view, function etc. The columns, parameters, return values and so on are in a array value for the 'Contains' key.

### GloopWholeDatabase.sql

This presents objects rather more neatly and provides the metadata about the database itself 

### TheGloopDocumentor.sql

This was my original attempt. I like it because it represents columns and parameters in a more compact way, but it can't be used for documenting a database.

### TheGloopDatabaseModel.sql

This provides a more compact model that is then ‘shrunk’ by PowerShell in a way that can’t be achieved just with SQL. It is done so as to provide more meaningful comparisons when used with Diff-Objects to compare databases.

### RunSQLScript.ps1

This is a PowerShell script for running a SQL batch that returns a string. It will run it on any number of SQL Servers and their databases as you wish.

