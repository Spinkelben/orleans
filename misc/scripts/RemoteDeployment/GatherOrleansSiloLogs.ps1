# Gets all logs from the silos defined in the OrleansRuntime.dll.config file.
#requires -version 2.0

param([string]$deploymentConfigFile, $outputPath)

$scriptDir = Split-Path -parent $MyInvocation.MyCommand.Definition
. $scriptDir\UtilityFunctions.ps1

$configXml = New-Object XML

if (($deploymentConfigFile -eq "/?") -or 
	($args[0] -eq "-?") -or
	($deploymentConfigFile -eq "/help") -or
	($args[0] -eq "-help") -or
	($deploymentConfigFile -eq "help") )
{
	WriteHostSafe Green -text ""
	WriteHostSafe Green -text "`tUsage:`t.\GatherOrleansLogs [deploymentConfigFile] [hostPath] [outputPath]"
	WriteHostSafe Green -text ""
	WriteHostSafe Green -text "`t`tdeployementConfigFile::`t[Optional] The path to the deployment configuration file. "
	WriteHostSafe Green -text "`t`t`t`t`t(i.e. ""Deployment.xml"")  Use quotes if the path has a spaces." 
	WriteHostSafe Green -text "`t`t`t`t`tDefault is Deployment.xml. "
	WriteHostSafe Green -text ""
    WriteHostSafe Green -text "`t`toutputPath :: [Optional] The path to place the log files."
    WriteHostSafe Green -text "`t`t`t`t`tDefault is [sourcePath]\Logs"
	WriteHostSafe Green -text ""
	WriteHostSafe Green -text "`tExample: .\GatherOrleansLogs ""C:\Projects\Orleans\Binaries\Debug\Deployment\Orleans\MSR-4MachineDeploy.xml"""
	WriteHostSafe Green -text "`tExample: .\GatherOrleansLogs ""C:\Projects\Orleans\Binaries\Debug\Deployment\Orleans\MSR-4MachineDeploy.xml"" ""\Logs-0922"" "
	WriteHostSafe Green -text ""
	return
}

# Change the path to where we think it should be (see http://huddledmasses.org/powershell-power-user-tips-current-directory/).
[Environment]::CurrentDirectory=(Get-Location -PSProvider FileSystem).ProviderPath

$configXml = Get-DeploymentConfiguration ([ref]$deploymentConfigFile) $scriptDir

# if we couldn't load the config file, the script cannot contiune.
if (!$configXml -or $configXml -eq "")
{
	WriteHostSafe -foregroundColor Red -text "     Deployment configuration file required to continue."
	WriteHostSafe -foregroundColor Red -text "          Please supply the name of the configuration file, or ensure that the default"
	WriteHostSafe -foregroundColor Red -text "          Deployment.xml file is available in the script directory."
	return
}

# Try to get the $localTargetPath from the target location node in the config file.
$deployTargetPath = $configXml.Deployment.TargetLocation.Path
if ($deployTargetPath)
{
	$logLocationPath = Split-Path $deployTargetPath -NoQualifier
}
else
{
	# Use the default if one is not found in the config file.
	$logLocationPath = "\Orleans"
}

if (!$outputPath)
{
    $outputPath = "$scriptDir\Logs"
}

if (!(Test-Path $outputPath))
{
	mkdir "$outputPath" -ErrorAction SilentlyContinue
}
        

$machineNames = Get-UniqueMachineNames $configXml $deploymentConfigFile

if(!$machineNames)
{
	WriteHostSafe -foregroundColor Red -text "     At least one target machine is required to continue."
	WriteHostSafe -foregroundColor Red -text ""
	return
}

if ($machineNames.Count -ge 1){$pluralizer = "s"} else {$pluralizer = ""}
WriteHostSafe -foregroundcolor Green -text ("Begin copying logs from {0} machine{1}." -f $machineNames.Count, $pluralizer)
foreach ($machine in $machineNames) 
{
        # copy all updated files, overwrite if newer
		WriteHostSafe -foregroundcolor Gray -text ("`tCopying logs from {0} to {1}." -f $machine, $outputPath)

		# XCopy Params:
		#	d	Copies only files whose source time is newer than the destination time.
		#	q	Don't display filenames while copying.
		#	y	Suppresses prompting.		
        $result = xcopy "\\$machine\c$\$logLocationPath\*.log" "$outputPath\" /d/q/y
		
		$messageColor = "Green"
		$filesCopied = $result.Split(" ")[0]
		if ($filesCopied -le 1)
		{
			if ($filesCopied -eq 1)
			{
				$result = $result.Replace("(s)", "")
			}
			else
			{
				$messageColor = "Yellow"
			}
		}
		WriteHostSafe -foregroundcolor "$messageColor" -text "`t`t $result"

        # copy any entries from Windows event logs, if present
        WriteHostSafe -foregroundcolor Gray -text ("`tChecking event logs on {0}..." -f $machine)
		$30days = New-TimeSpan -days 30
		$since = (Get-Date) - $30days
        $evLogs = Get-EventLog -LogName Application -ComputerName $machine -EntryType Error -After $since -Message *Orleans* -Newest 2
        if ($evLogs)
        {
            $evLogOut = "$outputPath\$machine-evlog.txt"
            WriteHostSafe -foregroundcolor Gray -text ("`tCopying event log entries from {0} to {1}" -f $machine, $evLogOut)
            Echo ("Windows Event Log Entried from {0}" -f $machine) | Out-File $evLogOut
            foreach ($ev in $evLogs)
            {
                Echo $ev.Message
                Echo $ev | Out-File -Append $evLogOut
                $msg = $ev.Message
                $msg = $msg.Replace("`r", " ")
                $msg = $msg.Replace("`n", " ")
                Echo $msg | Out-File -Append $evLogOut
            }
        }

        # copy any mini-dump files, if present
        $dumpFiles = "\\$machine\c$\$logLocationPath\*.dmp"
		if (Test-Path $dumpFiles)
		{
			WriteHostSafe -foregroundcolor Gray -text ("`tCopying Silo Mini-Dump files from {0} to {1}." -f $machine, $outputPath)

			$result = xcopy $dumpFiles "$outputPath\" /d/q/y

			$messageColor = "Green"
			$filesCopied = $result.Split(" ")[0]
			if ($filesCopied -le 1)
			{
				if ($filesCopied -eq 1)
				{
					$result = $result.Replace("(s)", "")
				}
				else
				{
					$messageColor = "Yellow"
				}
			}
			WriteHostSafe -foregroundcolor "$messageColor" -text "`t`t $result"
		}
}

WriteHostSafe -foregroundColor Green -text "Copy operation completed."
