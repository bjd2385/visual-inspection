# Utility/helper functions

function dedent([string[]]$text) {
    <#
    .SYNOPSIS
    Provide basic functionality of Python's `textwrap.dedent` function on multi-line
    strings for code readability.
    #>
    $i = $text | % { $_ -match "^(\s*)" | Out-Null 
                     $Matches[1].Length  } | sort | select -First 1

    $text.Split([Environment]::NewLine) -replace "^\s{$i}" -join [Environment]::NewLine
}
