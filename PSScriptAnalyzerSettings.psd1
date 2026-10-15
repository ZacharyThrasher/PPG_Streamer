@{
    # Scripts must run on Windows PowerShell 5.1 (built into Windows) and PowerShell 7.
    Rules        = @{
        PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1', '7.0') }
    }
    IncludeRules = @(
        'PSUseCompatibleSyntax',
        'PSAvoidUsingCmdletAliases',
        'PSAvoidAssignmentToAutomaticVariable',
        'PSPossibleIncorrectComparisonWithNull',
        'PSAvoidUsingInvokeExpression'
    )
}
