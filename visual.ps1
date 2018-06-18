#! /usr/bin/pwsh
# A simple PWSH script to walk an Evaluator through a visual inspection per 
# ITP 35022-SVC rev. D.


$welcome = "
    ____             __               __  __           ____  __                       
   / __ )____ __  __/ /____  _____   / / / /__  ____ _/ / /_/ /_  _________ _________ 
  / __  / __  / |/_/ __/ _ \/ ___/  / /_/ / _ \/ __  / / __/ __ \/ ___/ __  / ___/ _ \
 / /_/ / /_/ />  </ /_/  __/ /     / __  /  __/ /_/ / / /_/ / / / /__/ /_/ / /  /  __/
/_____/\__,_/_/|_|\__/\___/_/     /_/ /_/\___/\__,_/_/\__/_/ /_/\___/\__,_/_/   \___/
                                

ITP 35022-SVC rev. D - Visual Inspection
"

$LOG = $true

if ($isLinux) {
    $appendChar = "/"
} else {
    $appendChar = "\"
}

$PATH = (Get-Item -Path ".\").FullName + $appendChar

try {
    . ($PATH + "utility.ps1")
} catch {
    Write-Host "Error while loading supporting PS scripts"
    exit
}


## Global variables

$questions = 'ITP_35022_SVC_rev_D.json'  # Location of *.json visual inspection questions
$SN_redundancy_check = 2                 # Number of times to ask for input SN scan/type
$V6_recertification_range = 988482       # Cutoff SN for V6 by date
$V8_recertification_range = $null        # Cutoff SN for V8 by date
$V9_recertification_range = $null        # Cutoff SN for V9 by date

# TODO: Refine these ranges
$V6_upper_range_1 = 720000   # V6 valid serial number ranges
$V6_upper_range_2 = 1150000

$V6_lower_range_1 = 460000   
$V6_lower_range_2 = 470000

$V8_lower = 2000000          # V8 valid serial number ranges
$V8_upper = 2250000

$V9_lower = 3000000          # V9 valid serial number ranges
$V9_upper = 3300000


## Enums


enum Version 
{
    V6 = 1
    V8 = 2
    V9 = 3
}


enum DeviceCategory 
{
    REPAIR = 1
    RECERT = 2
    RENTAL = 3
}


## Base class


class Spectrum
{
    [int] $Serial_Number = 0
    [int] $Device_Type   = 0

    Spectrum()
    {
        $type = $this.GetType()

        if ($type -eq [Spectrum])
        {
            throw("Must inherit this type")
        }
    }

    [bool] Check_SN()
    {
        throw("Must override this method.")
    }

    [int] GetDeviceType()
    {
        <#
        .SYNOPSIS 
        Get the type of the device, be it a Repair, Recertification or Rental.        
        .DESCRIPTION
        Because Baxter's infusion devices are either recertified, repaired, or
        loaned, this function acquires this information from the end-user (evaluator).
        #>
        $prompt = dedent("Select one of the following:

            1 | Repair
            2 | Recertification
            3 | Rental

        ")
        $decision = 0
        $iterate = $true

        do {
            $in = Read-Host -Prompt $prompt

            if (!($in -match '^[0-9]{1}$')) 
            {
                Write-Warning "Input must be a single integer"
                continue
            }

            switch ([int]$in) 
            {
                { [DeviceCategory]::REPAIR }
                    { 
                        "Selected Repair" | Out-String -NoNewline
                        $iterate = $false
                        break 
                    }
                { [DeviceCategory]::RECERT } 
                    { 
                        "Selected Recert" | Out-String -NoNewline
                        $iterate = $false
                        break 
                    }
                { [DeviceCategory]::RENTAL }
                    { 
                        "Selected Rental" | Out-String -NoNewline
                        $iterate = $false
                        break 
                    }

                default { Write-Warning "Please select 1, 2, or 3" }
            }
        } while ($iterate)

        return [int]$decision
    }

    hidden [int] GetProperSNInput()
    {
        <#
        .SYNOPSIS
        Collect a proper serial number input, i.e. it must be a number.
        #>
        $regex = "^[1-9]{6,7}"

        $in = ""

        while ($true)
        {
            $in = Read-Host -Prompt "SN"

            if (!($in -match $regex))
            {
                Write-Warning "Please input a valid SN; received $in"
                continue
            }

            if ($in -match "^[4-9]")
            {
                Write-Warning "Please input a valid SN; received $in"
                continue
            }

            # TODO: Add more conditions as necessary

            break
        }

        return [int]$in
    }

    hidden [bool] GetYesNo()
    {
        <#
        .SYNOPSIS
        Collect `yes` and `no` answers to questions.
        .DESCRIPTION
        Overloaded `GetProperInput` method with type ([Int] -> [int]), which verifies
        correct serial numbers. This method is simply used to collect [y|n] answers
        to questions as an evaluator makes their way through a visual inspection.
        #>
        $regex = "^[yY](es)*"

        $in = Read-Host -Prompt "Continue? [y|n]"
        
        if ($in -match $regex)
        {
            return $true
        }
        else
        {
            return $false
        }
    }

    [int] GetSerialNumber()
    {   
        <#
        .SYNOPSIS 
        Get the serial number of the device from user in shell.        
        #>
        $input_SNs = New-Object System.Collections.ArrayList

        while ($true) 
        {
            # Get the SN of the device as input `$SN_redundancy_check` number of times
            foreach ($i in 1..$global:SN_redundancy_check)
            {
                $this.Serial_Number = $this.GetProperSNInput()
                $input_SNs.Add($this.Serial_Number)

                # At each step, if there's a discrepancy, restart the loop
                if (($input_SNs | Select -Unique).Count -ne 1) 
                {
                    Write-Warning "** SN mismatch - enter again"
                    $input_SNs = New-Object System.Collections.ArrayList
                    break   # start over with the first SN
                }
            }
        }

        return $input_SNs
    }

    [pscustomobject] Get_ITP_35022_SVC_Questions([String] $file_name) {
        <#
        .SYNOPSIS
        Open questions from *.json file.
        .DESCRIPTION

        .PARAMETER
        #>
        $json_input = (Get-Content $file_name | ConvertFrom-Json)

        return $json_input
    }

}


## Device Versions


class V6 : Spectrum
{
    V6([int] $serial_number)
    {
        <#
        .SYNOPSIS
        The SN is already known (unlikely).
        #>
        $this.Serial_Number = $serial_number
    }

    V6() {  }
    
    [bool] check_SN([int] $serial_number)
    {
        <#
        .SYNOPSIS
        Check the serial number of a particular device and ensure it falls within
        a specified range.
        .DESCRIPTION
        TODO: Refine
        For V6, valid SN ranges include [430000,470000]U[785000,1100000]⊂ Z^+ (?)
        #>
        # TODO: Refine these ranges
        return (!($global:serial_number -lt $global:V6_lower_range_1 -or 
                  $global:serial_number -gt $global:V6_lower_range_2 -or
                  $global:serial_number -lt $global:V6_upper_range_1 -or
                  $global:serial_number -gt $global:V6_upper_range_2))
    }

    [void] Start()
    {
        <#
        Main loop of visual inspection.
        #>
        $resultsForClipboard = ""

        while ($true)
        {
            $this.Serial_Number = $this.GetSerialNumber()
            $this.Device_Type = $this.GetDeviceType()
            
            # Copy results of visual inspection to clipboard
            Set-Clipboard -Value $resultsForClipboard
            
            dedent "           
            $([Environment]::NewLine) ** Copied results to clipboard. 
            You may begin another inspection" | Out-String
        }
    }
}


class V8 : Spectrum
{
    V8([int] $serial_number)
    {
        $this.Serial_Number = $serial_number
    }

    V8()
    {
        $this.Serial_Number = $this.GetSerialNumber()
    }

    [bool] check_SN([int] $serial_number)
    {
        # TODO: Refine these ranges
        return $serial_number -gt 2000000
    }
}


class V9 : Spectrum
{
    V9([int] $serial_number)
    {
        $this.Serial_Number = $serial_number
    }

    V9()
    {
        $this.Serial_Number = $this.GetSerialNumber()
    }

    [bool] check_SN([int] $serial_number)
    {
        # TODO: Refine these ranges
        return $serial_number -gt 3000000        
    }
}


## Setup


function GetDeviceVersion {
    <#
    .SYNOPSIS
    Simply gather the type of device we're working with, and because evaluators rarely
    change benches after starting. 
    
    (6/17/2018) Make an exception for V9.
    #>
    [OutputType([string])]
    $prompt = dedent "    Select the proper device version by typing [1|2|3]:
    
    1 | V6
    2 | V8
    3 | V9
    
    "

    $decision = ""
    $iterate = $true

    do {
        $decision = Read-Host -Prompt $prompt

        if (!($decision -match "^[0-9]{1}$")) 
        {
            Write-Warning "Input must be a single integer"
            continue
        }
        elseif (!($decision -match "^[1-3]{1}$"))
        {
            Write-Warning "Input must be 1, 2, or 3"
            continue
        }
    
        # Wait for integer conversion to avoid type conversion errors
        switch ([int]$decision) {
            { [Version]::V6 } 
                {
                    "Selected V6" | Out-String -NoNewline
                    $iterate = $false
                    break
                }
            { [Version]::V8 }
                { 
                    "Selected V8" | Out-String -NoNewline
                    $iterate = $false 
                    break
                }
            { [Version]::V9 }
                { 
                    Write-Warning "V9 has not been implemented"
                    #"Selected V9" | Out-String -NoNewline
                    #$iterate = $false
                    break
                }

            default { Write-Warning "Please select 1, 2, or 3"}
        }
    } while ($iterate)

    return $decision
} 


function Main 
{
    <#
    .SYNOPSIS 
    Set up the ExecutionPolicy of the script and create proper instance based on
    the device version an operator may be working with.
    #>
    [OutputType($null)]
    $welcome | Out-String

    try 
    {
        # Modify PS script execution policy for Windows
        Set-ExecutionPolicy -Scope CurrentUser Unrestricted
    } 
    catch [System.PlatformNotSupportedException] 
    {
        # Linux environment
        Write-Warning "Unable to set ExecutionPolicy"
        $regex = "^[yY](es)*"
        $decision = Read-Host -Prompt "Do you wish to proceed? [y|n]"

        if (!($decision -match $regex))
        {
            Write-Warning "Exiting"
            exit
        }
    }

    "" | Out-String

    $version = GetDeviceVersion

    # Create class instances
    switch ($version)
    {
        { [Version]::V6 } 
            { 
                "$([Environment]::NewLine)** Creating new V6 Infusion Device Instance" | Out-String
                $v6 = [V6]::New()
                $v6.Start()
            }
        { [Version]::V8 } { [V8]::New() }
        { [Version]::V9 } { [V9]::New() }
    }
}


Main
