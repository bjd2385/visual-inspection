# Utility/helper functions

function Write-Log {
    <#
    .SYNOPSIS
    Log data to a file.
    .DESCRIPTION
    Retrieved from https://blog.ipswitch.com/how-to-build-a-logging-function-in-powershell.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information','Warning','Error')]
        [string]$Severity = 'Information'
    )
              
    [pscustomobject]@{
        Time = (Get-Date -f g)
        Message = $Message
        Severity = $Severity
    } | Export-Csv -Path "log.csv" -Append -NoTypeInformation
}


function De-Dent([string[]]$text) {
    <#
    .SYNOPSIS
    Provide basic functionality of Python's `textwrap.dedent` function on multi-line
    strings for code readability.
    #>
    $i = $text | % { $_ -match "^(\s*)" | Out-Null 
                     $Matches[1].Length  } | sort | select -First 1

    $text.Split("`n") -replace "^\s{$i}" -join "`n"
}
