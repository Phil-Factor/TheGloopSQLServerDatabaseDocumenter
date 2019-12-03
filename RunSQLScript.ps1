import-Module sqlserver
<# a list of connection strings
for each of the target databaseinstances on which you'd like to run the code
#>
$ServerAndDatabaseList =
@(
 <# list of connection strings for each of the SQLservers that you need to execute code on #>
  @{ #provide a connection string for the instance
    'ServerConnectionString' = 'Server=MyFirstServer\sql2017;User Id=sa;Persist Security Info=False';
         #and a list of databases (DOS wildcards allowed)
    'Databases' = @('*') # do all
  },
  @{
    'ServerConnectionString' = 'Server=MySecondServer;User Id=PhilFactor;Persist Security Info=False';
    'Databases' = @('DaveDee', 'DozyBeaky', 'MickTitch')
  }
)
$FileNameEnd = 'AllMainObjects'#'AllObjects' #the unique part of the file you save the single string result in
#$SQLFileName = 'TheFilepathToTheSQL\TheGloopDocumentor.sql'# the file and path in which is your SQL Code
$SQLFileName = 'TheFilepathToTheSQL\TheSlimGloop.sql'# the file and path in which is your SQL Code

$RootDirectoryForOutputFile = "$env:USERPROFILE\JSONDocumentation" #the directory you want it in
$minimumCompatibilityLevel=130 #specify the minimum database compatibility level
$fileType='json' #the filetype of the file you save for each database.
$slash='+' #the string that you want to replace for the 'slash' in an instance name for files etc
# end of data area

$SQLContent = [IO.File]::ReadAllText($SQLFileName) #read the file into a variable in one gulp
# now create the directory (folder) for the output files if it doesn't exist
if (!(Test-Path -path $RootDirectoryForOutputFile -PathType Container))
{ $null = New-Item -ItemType directory -Path $RootDirectoryForOutputFile }
#Now for each instance and associated list of databases
$ServerAndDatabaseList | foreach {
  #for each instance/sever
  $csb = New-Object System.Data.Common.DbConnectionStringBuilder
  $csb.set_ConnectionString($_.ServerConnectionString) 
  # create an SMO connection get credentials if necessary
  if ($csb.'user id' -ne '') #then it is using SQL Server Credentials
  { <# Oh dear, we need to get the password, if we don't already know it #>
    $SqlEncryptedPasswordFile = `
    "$env:USERPROFILE\$($csb.'user id')-$($csb.server.Replace('\', $slash)).xml"
    # test to see if we know about the password in a secure string stored in the user area
    if (Test-Path -path $SqlEncryptedPasswordFile -PathType leaf)
    {
      #has already got this set for this login so fetch it
      $SqlCredentials = Import-CliXml $SqlEncryptedPasswordFile
      
    }
    else #then we have to ask the user for it (once only)
    {
      #hasn't got this set for this login
      $SqlCredentials = get-credential -Credential $csb.'user id'
      $SqlCredentials | Export-CliXml -Path $SqlEncryptedPasswordFile
    }
    $ServerConnection =
    new-object `
           "Microsoft.SqlServer.Management.Common.ServerConnection"`
    ($csb.server, $SqlCredentials.UserName, $SqlCredentials.GetNetworkCredential().password)
  }
  else
  {
    $ServerConnection =
    new-object `
           "Microsoft.SqlServer.Management.Common.ServerConnection" `
    ($csb.server)
  }
  <# all this work just to maintain passwords ! #>
  try # now we make an SMO connection  to the server, using the connection string
  {
    $srv = new-object ("Microsoft.SqlServer.Management.Smo.Server") $ServerConnection
  }
  catch
  {
    Write-error `
    "Could not connect to SQL Server instance $($csb.server) $($error[0]). Script is aborted"
    exit -1
  }
# get all the user databases that are at, or higher than your minimum compatibility level 
  $DatabaseNames = ($srv.databases | #get the list of servers
    where { $_.IsSystemObject -eq $false `
        -and (($_.CompatibilityLevel.ToString()| #check that they support JSON
            Select-String -Pattern '(\d+)' -All |
              Select Matches).matches[0].value) -ge $minimumCompatibilityLevel } |
               select name).name #and just get the name
  $DatabaseSpecs = $_.Databases #the database list we entered.
  $DatabaseList = @()
  #firstly do the database names
  $DatabaseList += $DatabaseSpecs | # get all the databases specified by name (no wildcards)
    where { $DatabaseNames -contains $_ }
  #now do the specs
  $databaseSpecs |
    where { $_ -like '*[*?]*' } | #do they match a wildcard expression
     foreach{ $wildcard = $_; $DatabaseList += $DatabaseNames | where { $_ -like $wildcard } }
  
  $DatabaseList | Sort-Object -Unique | #a database can be selected by more than one expression
    foreach {
      write-verbose "now doing $($_) on $($csb.server) "
      $Db = $_
      try #to execute the SQL in the file
      {
      $Contents = $srv.ConnectionContext.ExecuteScalar("
USE $Db
$SQLContent
 ")
     }
     catch
     {
      Write-error `
            "Could not execute the code $($csb.server) $($error[0]). Script is aborted"
      exit -1
     } #make sure that the folder exists for the subdirectory corresponding to the server
    if (!(Test-Path -path "$RootDirectoryForOutputFile\$($csb.server.Replace('\', $slash))" -PathType Container))
    { $null = New-Item -ItemType directory -Path "$RootDirectoryForOutputFile\$($csb.server.Replace('\', $slash))" }
    #output it to the file
    $Contents>"$RootDirectoryForOutputFile\$($csb.server.Replace('\', $slash))\$Db-$FileNameEnd.$FileType"
  }
}
