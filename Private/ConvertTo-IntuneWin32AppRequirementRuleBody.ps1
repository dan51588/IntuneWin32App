function ConvertTo-IntuneWin32AppRequirementRuleBody {
    <#
    .SYNOPSIS
        Convert a requirement rule into the Win32 app body properties used by Graph.

    .DESCRIPTION
        Convert a requirement rule created by New-IntuneWin32AppRequirementRule into the Win32 app body properties used by Graph, e.g. minimumSupportedWindowsRelease,
        allowedArchitectures and minimumMemoryInMB. When no requirement rule is passed, the default requirement properties are returned.
        Invalid requirement rule input throws a terminating error.

    .PARAMETER RequirementRule
        Provide an OrderedDictionary object as requirement rule, created by New-IntuneWin32AppRequirementRule.

    .PARAMETER IncludeUnsetProperties
        Specify to include the optional requirement properties that are not set in the requirement rule with a null value, which clears them on an existing Win32 app.

    .NOTES
        Created:     2026-09-26
        Updated:     2026-09-26

        Version history:
        1.0.0 - (2026-09-26) Function created
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $false, HelpMessage = "Provide an OrderedDictionary object as requirement rule, created by New-IntuneWin32AppRequirementRule.")]
        [AllowNull()]
        [System.Collections.Specialized.OrderedDictionary]$RequirementRule,

        [parameter(Mandatory = $false, HelpMessage = "Specify to include the optional requirement properties that are not set in the requirement rule with a null value.")]
        [switch]$IncludeUnsetProperties
    )
    $OptionalProperties = @("minimumFreeDiskSpaceInMB", "minimumMemoryInMB", "minimumNumberOfProcessors", "minimumCpuSpeedInMHz")
    $KnownProperties = @("allowedArchitectures", "applicableArchitectures", "minimumSupportedWindowsRelease") + $OptionalProperties

    # Default requirement properties when no requirement rule is passed
    if ($null -eq $RequirementRule) {
        return [ordered]@{
            "minimumSupportedWindowsRelease" = "2H20"
            "applicableArchitectures" = "x64,x86"
        }
    }

    # Warn about properties that are not used, e.g. from a requirement rule constructed manually or by an older version of the module
    foreach ($Key in $RequirementRule.Keys) {
        if ($Key -notin $KnownProperties) {
            Write-Warning -Message "RequirementRule property '$($Key)' is not supported and will be ignored. Use New-IntuneWin32AppRequirementRule to create requirement rules."
        }
    }

    if ([string]::IsNullOrEmpty($RequirementRule["minimumSupportedWindowsRelease"])) {
        throw "RequirementRule is missing required 'minimumSupportedWindowsRelease' property. Use New-IntuneWin32AppRequirementRule to create requirement rules."
    }
    $RequirementRuleBody = [ordered]@{
        "minimumSupportedWindowsRelease" = $RequirementRule["minimumSupportedWindowsRelease"]
    }

    # Use the modern allowedArchitectures property when available, otherwise fall back to the legacy applicableArchitectures property
    if (-not [string]::IsNullOrEmpty($RequirementRule["allowedArchitectures"])) {
        $RequirementRuleBody.Add("allowedArchitectures", $RequirementRule["allowedArchitectures"])
        $RequirementRuleBody.Add("applicableArchitectures", "none")
    }
    elseif ((-not [string]::IsNullOrEmpty($RequirementRule["applicableArchitectures"])) -and ($RequirementRule["applicableArchitectures"] -ne "none")) {
        $RequirementRuleBody.Add("applicableArchitectures", $RequirementRule["applicableArchitectures"])
    }
    else {
        throw "RequirementRule is missing required 'allowedArchitectures' property. Use New-IntuneWin32AppRequirementRule to create requirement rules."
    }

    foreach ($OptionalProperty in $OptionalProperties) {
        $Value = $RequirementRule[$OptionalProperty]
        if ($null -ne $Value) {
            $ParsedValue = 0
            if (($Value -is [bool]) -or (-not [int]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ParsedValue)) -or ($ParsedValue -lt 0)) {
                throw "Invalid value '$($Value)' for RequirementRule property '$($OptionalProperty)', it must be a whole number of 0 or greater"
            }
            $RequirementRuleBody.Add($OptionalProperty, $ParsedValue)
        }
        elseif ($IncludeUnsetProperties) {
            $RequirementRuleBody.Add($OptionalProperty, $null)
        }
    }

    return $RequirementRuleBody
}
