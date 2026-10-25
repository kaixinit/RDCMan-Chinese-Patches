param([Parameter(Mandatory=$true)][string]$WorkRoot,[Parameter(Mandatory=$true)][string]$CecilPath)
$ErrorActionPreference='Stop'
$taskRoot=$WorkRoot
. (Join-Path $PSScriptRoot 'Common.ps1')
Add-Type -Path $CecilPath
$taskResolver=[Mono.Cecil.DefaultAssemblyResolver]::new()
$taskResolver.AddSearchDirectory((Join-Path $taskRoot 'references'))
$taskReader=[Mono.Cecil.ReaderParameters]::new()
$taskReader.AssemblyResolver=$taskResolver
$taskSourcePath = Join-Path $taskRoot 'RDCMan.original.dll'
if ((Get-FileHash -LiteralPath $taskSourcePath -Algorithm SHA256).Hash -ne '61EB34B32EEF138C79DE30B43D0E92E43CEC355C7E67AB4B157032C568E6CE73') { throw 'Unexpected source assembly' }
$taskOriginal = [Mono.Cecil.ModuleDefinition]::ReadModule($taskSourcePath,$taskReader)
$taskPatched = [Mono.Cecil.ModuleDefinition]::ReadModule($taskSourcePath,$taskReader)
$taskPatches = Get-Content -LiteralPath (Join-Path $taskRoot 'patches.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskMethodMap = @{}
foreach ($taskType in $taskPatched.GetTypes()) { foreach ($taskMethod in $taskType.Methods) { $taskMethodMap[$taskMethod.FullName]=$taskMethod } }
$taskPatchMap = @{}
foreach ($taskPatch in $taskPatches) {
    $taskMethod = $taskMethodMap[$taskPatch.Method]
    $taskInstruction = $taskMethod.Body.Instructions[$taskPatch.Index]
    if ($taskInstruction.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldstr -or $taskInstruction.Operand -cne $taskPatch.English) { throw ('Patch location mismatch: '+$taskPatch.Id) }
    $taskInstruction.Operand = [string]$taskPatch.Chinese
    $taskPatchMap[$taskPatch.Method+'|'+$taskPatch.Index]=[string]$taskPatch.Chinese
}
$taskProductAttribute=@($taskPatched.Assembly.CustomAttributes | Where-Object { $_.AttributeType.FullName -eq 'System.Reflection.AssemblyProductAttribute' })
if ($taskProductAttribute.Count -ne 1 -or $taskProductAttribute[0].ConstructorArguments[0].Value -cne 'Remote Desktop Connection Manager') { throw 'Unexpected product attribute' }
$taskProductAttribute[0].ConstructorArguments[0]=[Mono.Cecil.CustomAttributeArgument]::new($taskPatched.TypeSystem.String,'RDCMan 中文学习版（非官方）')
$taskOutputPath = Join-Path $taskRoot 'RDCMan.zh.dll'
$taskPatched.Write($taskOutputPath)
$taskPatched.Dispose()
$taskReopened = [Mono.Cecil.ModuleDefinition]::ReadModule($taskOutputPath,$taskReader)
$taskReloadedMethods=@{}
foreach ($taskType in $taskReopened.GetTypes()) { foreach ($taskMethod in $taskType.Methods) { $taskReloadedMethods[$taskMethod.FullName]=$taskMethod } }
$taskMethodCount=0; $taskInstructionCount=0; $taskChangeCount=0
foreach ($taskType in $taskOriginal.GetTypes()) {
    foreach ($taskMethod in $taskType.Methods) {
        $taskNewMethod=$taskReloadedMethods[$taskMethod.FullName]
        if ($null -eq $taskNewMethod -or $taskMethod.HasBody -ne $taskNewMethod.HasBody) { throw 'Method changed or missing' }
        $taskMethodCount++
        if (-not $taskMethod.HasBody) { continue }
        if ($taskMethod.Body.Instructions.Count -ne $taskNewMethod.Body.Instructions.Count) { throw 'Instruction count changed' }
        for ($taskIndex=0; $taskIndex -lt $taskMethod.Body.Instructions.Count; $taskIndex++) {
            $taskOldInstruction=$taskMethod.Body.Instructions[$taskIndex]
            $taskNewInstruction=$taskNewMethod.Body.Instructions[$taskIndex]
            $taskKey=$taskMethod.FullName+'|'+$taskIndex
            if ($taskOldInstruction.OpCode.Code -ne $taskNewInstruction.OpCode.Code) { throw 'OpCode changed' }
            if ($taskPatchMap.ContainsKey($taskKey)) {
                if ($taskNewInstruction.Operand -cne $taskPatchMap[$taskKey]) { throw 'Translation did not persist' }
                $taskChangeCount++
            } elseif ($taskOldInstruction.ToString() -cne $taskNewInstruction.ToString()) { throw ('Unexpected operand change: '+$taskKey) }
            $taskInstructionCount++
        }
        if ($taskMethod.Body.ExceptionHandlers.Count -ne $taskNewMethod.Body.ExceptionHandlers.Count) { throw 'Exception handlers changed' }
        if ((($taskMethod.Body.Variables | ForEach-Object { $_.VariableType.FullName }) -join '|') -cne (($taskNewMethod.Body.Variables | ForEach-Object { $_.VariableType.FullName }) -join '|')) { throw 'Local variable types changed' }
    }
}
if ($taskChangeCount -ne $taskPatches.Count) { throw 'Not all translations were verified' }
if (($taskOriginal.AssemblyReferences.FullName -join '|') -cne ($taskReopened.AssemblyReferences.FullName -join '|')) { throw 'Assembly references changed' }
$taskNewResourceMap=@{}
foreach ($taskResource in $taskReopened.Resources) { $taskNewResourceMap[$taskResource.Name]=$taskResource }
foreach ($taskResource in $taskOriginal.Resources) {
    if ($taskResource -is [Mono.Cecil.EmbeddedResource]) {
        $taskOriginalHash=(Get-BytesSHA256 $taskResource.GetResourceData())
        $taskNewHash=(Get-BytesSHA256 $taskNewResourceMap[$taskResource.Name].GetResourceData())
        if ($taskOriginalHash -ne $taskNewHash) { throw 'Binary resource changed' }
    }
}
$taskReloadedProduct=@($taskReopened.Assembly.CustomAttributes | Where-Object { $_.AttributeType.FullName -eq 'System.Reflection.AssemblyProductAttribute' })[0].ConstructorArguments[0].Value
if ($taskReloadedProduct -cne 'RDCMan 中文学习版（非官方）') { throw 'Study product isolation did not persist' }
$taskReport=[PSCustomObject]@{Translations=$taskChangeCount;MethodsVerified=$taskMethodCount;InstructionsVerified=$taskInstructionCount;ResourcesVerified=$taskOriginal.Resources.Count;AssemblyReferencesUnchanged=$true;OnlyApprovedStringOperandsChanged=$true;AdditionalMetadataChange='AssemblyProductAttribute for an isolated learning settings directory';StudyProductName=$taskReloadedProduct;SourceAssemblySHA256=(Get-FileHash -LiteralPath $taskSourcePath -Algorithm SHA256).Hash;LocalizedAssemblySHA256=(Get-FileHash -LiteralPath $taskOutputPath -Algorithm SHA256).Hash}
$taskReport | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskRoot 'assembly-verification.json') -Encoding utf8
$taskReport | ConvertTo-Json
$taskOriginal.Dispose(); $taskReopened.Dispose()
$taskResolver.Dispose()
