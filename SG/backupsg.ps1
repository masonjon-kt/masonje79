# Define SQL connection parameters
$server = "N060POSSQL11.kroger.com,1675"
$database = "StoreGazerV2"
$user = "SVC5638SGDBP"
$password = "CTejuGAjnOOqKDzcQoN7Q27lLL1dy"

$query = "select top 100 * from user_settings
where  user_id = '0'
order by setting
"
$outputFile = "results.csv"

# Build connection string
$connectionString = "Server=$server;Database=$database;User Id=$user;Password=$password;"

# Create SQL connection and command
$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString
$command = $connection.CreateCommand()
$command.CommandText = $query

# Execute query and export results
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
$table = New-Object System.Data.DataTable
$adapter.Fill($table) | Out-Null
$table | Export-Csv -Path $outputFile -NoTypeInformation

# Clean up
$connection.Close()