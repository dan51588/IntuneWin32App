function Merge-IntuneWin32AppReturnCode {
    <#
    .SYNOPSIS
        Merge return code input with an existing set of return codes for a Win32 application.

    .DESCRIPTION
        Merge return code input with an existing set of return codes for a Win32 application, e.g. the return codes currently configured on an app
        or the default set of return codes. Input is validated before any merging takes place and a terminating error is thrown for invalid input,
        so that callers never send a partially processed set of return codes to Graph. The changes compared to the base set are written as verbose output.

    .PARAMETER BaseReturnCode
        Specify the existing set of return codes, either as hash-tables or as objects returned from Graph, that input is merged into.

    .PARAMETER ReturnCode
        Provide an array of a single or multiple hash-tables with return code information to add, or to change the type of an existing return code.

    .PARAMETER RemoveReturnCode
        Specify one or more return code values to remove from the base set of return codes.

    .PARAMETER Action
        Specify Merge to add or update return codes in the base set, or Replace to discard the base set and use only the return codes from the ReturnCode parameter.

    .NOTES
        Created:     2026-09-23
        Updated:     2026-09-23

        Version history:
        1.0.0 - (2026-09-23) Function created
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $false, HelpMessage = "Specify the existing set of return codes that input is merged into.")]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$BaseReturnCode,

        [parameter(Mandatory = $false, HelpMessage = "Provide an array of a single or multiple hash-tables with return code information.")]
        [AllowNull()]
        [System.Collections.Hashtable[]]$ReturnCode,

        [parameter(Mandatory = $false, HelpMessage = "Specify one or more return code values to remove from the base set of return codes.")]
        [AllowNull()]
        [int[]]$RemoveReturnCode,

        [parameter(Mandatory = $false, HelpMessage = "Specify Merge to add or update return codes in the base set, or Replace to use only the return codes from the ReturnCode parameter.")]
        [ValidateSet("Merge", "Replace")]
        [string]$Action = "Merge"
    )
    # Graph expects these exact enum values, input is matched case-insensitively and converted to this casing
    $ValidReturnCodeTypes = @("success", "softReboot", "hardReboot", "retry", "failed")

    # Validate all input before merging anything
    if (($Action -eq "Replace") -and ($null -eq $ReturnCode -or $ReturnCode.Count -eq 0)) {
        throw "ReturnCodeAction 'Replace' requires at least one return code from the ReturnCode parameter"
    }
    if (($Action -eq "Replace") -and ($RemoveReturnCode.Count -ge 1)) {
        throw "RemoveReturnCode cannot be combined with ReturnCodeAction 'Replace', the replacement set is exactly what is passed in the ReturnCode parameter"
    }

    $InputReturnCodes = New-Object -TypeName "System.Collections.Generic.List[System.Collections.Specialized.OrderedDictionary]"
    foreach ($ReturnCodeItem in $ReturnCode) {
        if ($null -eq $ReturnCodeItem) {
            throw "ReturnCode input contains a null item. Use New-IntuneWin32AppReturnCode to create return codes."
        }
        if (-not ($ReturnCodeItem.ContainsKey("returnCode") -and $ReturnCodeItem.ContainsKey("type"))) {
            throw "ReturnCode object must contain both 'returnCode' and 'type' properties. Use New-IntuneWin32AppReturnCode to create return codes."
        }

        # Return code must be a whole number within the Int32 range, e.g. 3010 or -2147024891
        $ReturnCodeValue = $ReturnCodeItem["returnCode"]
        $ParsedReturnCode = 0
        if (($ReturnCodeValue -is [bool]) -or (-not [int]::TryParse([string]$ReturnCodeValue, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ParsedReturnCode))) {
            throw "Invalid return code value '$($ReturnCodeValue)', it must be a whole number within the range $([int]::MinValue) to $([int]::MaxValue)"
        }

        $ReturnCodeType = $ValidReturnCodeTypes | Where-Object { $_ -eq [string]$ReturnCodeItem["type"] } | Select-Object -First 1
        if ($null -eq $ReturnCodeType) {
            throw "Invalid return code type '$($ReturnCodeItem["type"])' for return code $($ParsedReturnCode). Valid types are: $($ValidReturnCodeTypes -join ', ')"
        }

        if ($InputReturnCodes | Where-Object { $_.returnCode -eq $ParsedReturnCode }) {
            throw "Return code $($ParsedReturnCode) was specified more than once in the ReturnCode parameter"
        }
        if ($ParsedReturnCode -in $RemoveReturnCode) {
            throw "Return code $($ParsedReturnCode) was specified in both the ReturnCode and RemoveReturnCode parameters"
        }

        $InputReturnCodes.Add([ordered]@{ "returnCode" = $ParsedReturnCode; "type" = $ReturnCodeType })
    }

    # Normalize the base set, which could be hash-tables or objects returned from Graph, into new objects to avoid modifying the input
    $BaseReturnCodes = New-Object -TypeName "System.Collections.Generic.List[System.Collections.Specialized.OrderedDictionary]"
    foreach ($BaseReturnCodeItem in $BaseReturnCode) {
        if ($null -ne $BaseReturnCodeItem) {
            $BaseReturnCodes.Add([ordered]@{ "returnCode" = [int]$BaseReturnCodeItem.returnCode; "type" = [string]$BaseReturnCodeItem.type })
        }
    }

    # Construct the resulting set of return codes
    $ResultReturnCodes = New-Object -TypeName "System.Collections.Generic.List[System.Collections.Specialized.OrderedDictionary]"
    switch ($Action) {
        "Replace" {
            foreach ($InputReturnCodeItem in $InputReturnCodes) {
                $ResultReturnCodes.Add($InputReturnCodeItem)
            }
        }
        "Merge" {
            foreach ($BaseReturnCodeItem in $BaseReturnCodes) {
                $ResultReturnCodes.Add([ordered]@{ "returnCode" = $BaseReturnCodeItem.returnCode; "type" = $BaseReturnCodeItem.type })
            }

            foreach ($RemoveReturnCodeItem in ($RemoveReturnCode | Select-Object -Unique)) {
                $ExistingReturnCode = $ResultReturnCodes | Where-Object { $_.returnCode -eq $RemoveReturnCodeItem } | Select-Object -First 1
                if ($null -eq $ExistingReturnCode) {
                    Write-Warning -Message "Return code $($RemoveReturnCodeItem) specified for removal does not exist in the current set of return codes"
                }
                else {
                    $ResultReturnCodes.Remove($ExistingReturnCode) | Out-Null
                }
            }

            foreach ($InputReturnCodeItem in $InputReturnCodes) {
                $ExistingReturnCode = $ResultReturnCodes | Where-Object { $_.returnCode -eq $InputReturnCodeItem.returnCode } | Select-Object -First 1
                if ($null -eq $ExistingReturnCode) {
                    $ResultReturnCodes.Add($InputReturnCodeItem)
                }
                else {
                    $ExistingReturnCode.type = $InputReturnCodeItem.type
                }
            }
        }
    }

    # Output the changes compared to the base set as verbose output
    $AddedCount = 0; $ChangedCount = 0; $RemovedCount = 0; $UnchangedCount = 0
    foreach ($BaseReturnCodeItem in $BaseReturnCodes) {
        $ResultReturnCode = $ResultReturnCodes | Where-Object { $_.returnCode -eq $BaseReturnCodeItem.returnCode } | Select-Object -First 1
        if ($null -eq $ResultReturnCode) {
            Write-Verbose -Message "Return code removed: $($BaseReturnCodeItem.returnCode) ($($BaseReturnCodeItem.type))"
            $RemovedCount++
        }
        elseif ($ResultReturnCode.type -cne $BaseReturnCodeItem.type) {
            Write-Verbose -Message "Return code changed: $($BaseReturnCodeItem.returnCode) ($($BaseReturnCodeItem.type) -> $($ResultReturnCode.type))"
            $ChangedCount++
        }
        else {
            Write-Verbose -Message "Return code unchanged: $($BaseReturnCodeItem.returnCode) ($($BaseReturnCodeItem.type))"
            $UnchangedCount++
        }
    }
    foreach ($ResultReturnCodeItem in $ResultReturnCodes) {
        if (-not ($BaseReturnCodes | Where-Object { $_.returnCode -eq $ResultReturnCodeItem.returnCode })) {
            Write-Verbose -Message "Return code added: $($ResultReturnCodeItem.returnCode) ($($ResultReturnCodeItem.type))"
            $AddedCount++
        }
    }
    if (($AddedCount + $ChangedCount + $RemovedCount) -eq 0) {
        Write-Verbose -Message "No changes to return codes, $($UnchangedCount) return codes unchanged"
    }
    else {
        Write-Verbose -Message "Return code changes: $($AddedCount) added, $($ChangedCount) changed, $($RemovedCount) removed, $($UnchangedCount) unchanged"
    }

    # Warn about return code sets that are valid for Graph but most likely a mistake
    if (-not ($ResultReturnCodes | Where-Object { $_.type -eq "success" })) {
        Write-Warning -Message "The resulting set of return codes contains no 'success' return code, every installation of the Win32 app will be reported as failed"
    }
    $BaseSuccessCode = $BaseReturnCodes | Where-Object { ($_.returnCode -eq 0) -and ($_.type -eq "success") }
    $ResultZeroCode = $ResultReturnCodes | Where-Object { $_.returnCode -eq 0 } | Select-Object -First 1
    if (($null -ne $BaseSuccessCode) -and (($null -eq $ResultZeroCode) -or ($ResultZeroCode.type -ne "success"))) {
        Write-Warning -Message "Return code 0 is no longer configured as 'success', installations that exit with code 0 will not be reported as successful"
    }

    # Return as a single array object, to ensure a set with a single return code is still converted to a JSON array
    return , $ResultReturnCodes.ToArray()
}
