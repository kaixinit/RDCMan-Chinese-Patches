param([Parameter(Mandatory=$true)][string]$WorkRoot,[Parameter(Mandatory=$true)][string]$CecilPath)
$ErrorActionPreference='Stop'
$taskRoot=$WorkRoot
. (Join-Path $PSScriptRoot 'Common.ps1')
Add-Type -Path $CecilPath
$taskInput=Join-Path $taskRoot 'RDCMan.zh.exe'
$taskBaseBytes=[IO.File]::ReadAllBytes($taskInput)
$taskModule=[Mono.Cecil.ModuleDefinition]::ReadModule([IO.MemoryStream]::new($taskBaseBytes))
$taskBase=[Mono.Cecil.ModuleDefinition]::ReadModule([IO.MemoryStream]::new($taskBaseBytes))
$taskOriginalMethods=@{}
foreach($taskT in $taskModule.GetTypes()){foreach($taskM in $taskT.Methods){$taskOriginalMethods[$taskM.FullName]=$taskM}}
$taskChanges=[System.Collections.Generic.List[object]]::new()
$taskAllowed=[System.Collections.Generic.HashSet[string]]::new()
$taskOps=[Mono.Cecil.Cil.OpCodes]

function Find-Method([string]$Type,[string]$Name){
  $taskFound=@($taskModule.GetTypes() | Where-Object FullName -CEQ $Type | ForEach-Object Methods | Where-Object Name -CEQ $Name)
  if($taskFound.Count -ne 1){throw ('Expected exactly one method: '+$Type+'::'+$Name)}
  return $taskFound[0]
}
function Add-Change($Method,[string]$Description){
  [void]$taskAllowed.Add($Method.FullName)
  $taskChanges.Add([PSCustomObject]@{Method=$Method.FullName;Reason=$Description})
}
function Add-BeforeRetCall($Method,$Target,[string]$Description){
  $taskIl=$Method.Body.GetILProcessor()
  $taskRets=@($Method.Body.Instructions | Where-Object {$_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ret})
  foreach($taskRet in $taskRets){
    # Keep all existing branch targets pointing at the call, rather than skipping it.
    $taskRet.OpCode=$taskOps::Call; $taskRet.Operand=$Target
    $taskIl.InsertAfter($taskRet,[Mono.Cecil.Cil.Instruction]::Create($taskOps::Ret))
  }
  Add-Change $Method $Description
}

# Display names are separate from the English identifiers used by settings and enum values.
$taskHelper=[Mono.Cecil.TypeDefinition]::new('RdcMan','ChineseStudyText',([Mono.Cecil.TypeAttributes](([int][Mono.Cecil.TypeAttributes]::NotPublic) -bor ([int][Mono.Cecil.TypeAttributes]::Abstract) -bor ([int][Mono.Cecil.TypeAttributes]::Sealed) -bor ([int][Mono.Cecil.TypeAttributes]::BeforeFieldInit))),$taskModule.TypeSystem.Object)
$taskModule.Types.Add($taskHelper)
$taskStringEquals=$null; $taskControlSetWidth=$null
foreach($taskM in $taskOriginalMethods.Values){
  if(-not $taskM.HasBody){continue}
  foreach($taskI in $taskM.Body.Instructions){
    if($taskI.Operand -is [Mono.Cecil.MethodReference]){
      if($taskI.Operand.FullName -ceq 'System.Boolean System.String::op_Equality(System.String,System.String)'){$taskStringEquals=$taskI.Operand}
      if($taskI.Operand.FullName -ceq 'System.Void System.Windows.Forms.Control::set_Width(System.Int32)'){$taskControlSetWidth=$taskI.Operand}
    }
  }
}
if($null -eq $taskStringEquals -or $null -eq $taskControlSetWidth){throw 'Required framework references missing'}
function New-StringMap([string]$Name,$Pairs){
  $taskM=[Mono.Cecil.MethodDefinition]::new($Name,([Mono.Cecil.MethodAttributes](([int][Mono.Cecil.MethodAttributes]::Assembly) -bor ([int][Mono.Cecil.MethodAttributes]::Static) -bor ([int][Mono.Cecil.MethodAttributes]::HideBySig))),$taskModule.TypeSystem.String)
  $taskM.Parameters.Add([Mono.Cecil.ParameterDefinition]::new('value',[Mono.Cecil.ParameterAttributes]::None,$taskModule.TypeSystem.String))
  $taskHelper.Methods.Add($taskM)
  $taskIl=$taskM.Body.GetILProcessor()
  foreach($taskPair in $Pairs){
    if($taskPair -isnot [array] -or $taskPair.Count -ne 2){throw ('Invalid string map pair in '+$Name)}
    $taskNext=[Mono.Cecil.Cil.Instruction]::Create($taskOps::Nop)
    $taskIl.Emit($taskOps::Ldarg_0)
    $taskIl.Emit($taskOps::Ldstr,[string]$taskPair[0])
    $taskIl.Emit($taskOps::Call,$taskStringEquals)
    $taskIl.Emit($taskOps::Brfalse,$taskNext)
    $taskIl.Emit($taskOps::Ldstr,[string]$taskPair[1])
    $taskIl.Emit($taskOps::Ret)
    $taskIl.Append($taskNext)
  }
  $taskIl.Emit($taskOps::Ldarg_0); $taskIl.Emit($taskOps::Ret)
  return $taskM
}
$taskPatches=Get-Content -LiteralPath (Join-Path $taskRoot 'patches.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskCanonicalPairs=@()
foreach($taskEnglish in 'Connected','Connect To','Favorites','Recent','Reconnect'){
  $taskP=@($taskPatches | Where-Object {$_.English -ceq $taskEnglish -and $_.Type -match '^RdcMan\.(ConnectedGroup|ConnectToGroup|FavoritesGroup|RecentlyUsedGroup|ReconnectGroup)$'})[0]
  if($null -eq $taskP){throw 'Built-in caption translation missing'}
  $taskCanonicalPairs+=,@([string]$taskP.Chinese,[string]$taskP.English)
}
$taskCaptionPairs=@(
  @('Left','左侧'),@('Right','右侧'),@('Top','顶部'),@('Bottom','底部'),
  @('Dock','停靠'),@('AutoHide','自动隐藏'),@('Hide','隐藏'),@('Fill','填充'),@('None','无'),
  @('DisplayName','显示名称'),@('ServerName','服务器名称'),@('Parent','父级分组'),@('Comment','备注'),
  @('Matches','匹配'),@('DoesNotMatch','不匹配'),@('Any','任一'),@('All','全部'),
  @('Active','活动'),@('Connected','已连接'),@('ConnectQuery','正在查询'),@('Shadow','远程控制'),
  @('Disconnected','已断开'),@('Idle','空闲'),@('Listen','侦听'),@('Reset','正在重置'),@('Down','已关闭'),@('Init','正在初始化'),
  @('Remote Desktop Connection Manager','远程桌面连接管理器')
)
$taskCanonical=New-StringMap 'CanonicalGroupKey' $taskCanonicalPairs
$taskCaption=New-StringMap 'Caption' $taskCaptionPairs
$taskTitleCaption=New-StringMap 'TitleCaption' (,@('远程桌面连接管理器（中文学习版）','远程桌面连接管理器'))
$taskProfileType=@($taskModule.GetTypes() | Where-Object FullName -ceq 'RdcMan.CredentialsProfile')[0]
$taskProfileCaption=[Mono.Cecil.MethodDefinition]::new('ProfileCaption',([Mono.Cecil.MethodAttributes](([int][Mono.Cecil.MethodAttributes]::Assembly) -bor ([int][Mono.Cecil.MethodAttributes]::Static) -bor ([int][Mono.Cecil.MethodAttributes]::HideBySig))),$taskModule.TypeSystem.String)
$taskProfileCaption.Parameters.Add([Mono.Cecil.ParameterDefinition]::new('label',[Mono.Cecil.ParameterAttributes]::None,$taskModule.TypeSystem.String))
$taskProfileCaption.Parameters.Add([Mono.Cecil.ParameterDefinition]::new('value',[Mono.Cecil.ParameterAttributes]::None,$taskModule.TypeSystem.Object))
$taskHelper.Methods.Add($taskProfileCaption)
$taskProfileIl=$taskProfileCaption.Body.GetILProcessor()
$taskProfileReturn=[Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldarg_0)
$taskProfileIl.Emit($taskOps::Ldarg_1)
$taskProfileIl.Emit($taskOps::Isinst,$taskProfileType)
$taskProfileIl.Emit($taskOps::Brfalse,$taskProfileReturn)
$taskProfileIl.Emit($taskOps::Ldarg_0)
$taskProfileIl.Emit($taskOps::Ldstr,'Custom')
$taskProfileIl.Emit($taskOps::Call,$taskStringEquals)
$taskProfileIl.Emit($taskOps::Brfalse,$taskProfileReturn)
$taskProfileIl.Emit($taskOps::Ldstr,'自定义')
$taskProfileIl.Emit($taskOps::Ret)
$taskProfileIl.Append($taskProfileReturn)
$taskProfileIl.Emit($taskOps::Ret)
$taskComboToString=Find-Method 'RdcMan.ValueComboBox`1/ComboBoxItem`1' 'ToString'
$taskNameRef=@($taskComboToString.Body.Instructions | Where-Object {$_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldfld -and $_.Operand.Name -ceq 'Name'})[0].Operand
$taskValueParam=$taskComboToString.DeclaringType.GenericParameters[1]
$taskValueRef=[Mono.Cecil.FieldReference]::new('Value',$taskValueParam,$taskNameRef.DeclaringType)
$taskComboIl=$taskComboToString.Body.GetILProcessor()
$taskComboRet=@($taskComboToString.Body.Instructions | Where-Object {$_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ret})[0]
$taskComboRet.OpCode=$taskOps::Ldarg_0; $taskComboRet.Operand=$null
$taskInsert=$taskComboRet
foreach($taskNew in @(
  [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldfld,$taskValueRef),
  [Mono.Cecil.Cil.Instruction]::Create($taskOps::Box,$taskValueParam),
  [Mono.Cecil.Cil.Instruction]::Create($taskOps::Call,$taskProfileCaption),
  [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ret)
)){$taskComboIl.InsertAfter($taskInsert,$taskNew);$taskInsert=$taskNew}
Add-Change $taskComboToString 'Translate only the rendered Custom credential profile; retain raw Name for FindItem and raw profile identity for storage'
Add-BeforeRetCall (Find-Method 'RdcMan.BuiltInVirtualGroup`1' 'get_ConfigName') $taskCanonical 'Retain canonical English settings keys independently of translated tree captions'
foreach($taskLambda in '<CreateServerTreePage>b__36_0','<CreateServerTreePage>b__36_1'){
  Add-BeforeRetCall (Find-Method 'RdcMan.GlobalOptionsDialog/<>c' $taskLambda) $taskCaption 'Translate enum captions only; selected enum values and serialization stay unchanged'
}
foreach($taskSpec in @(
  @('RdcMan.SmartGroupPropertiesTabPage/SmartRuleControl/<>c','<.ctor>b__0_0'),
  @('RdcMan.SmartGroupPropertiesTabPage/SmartRuleControl/<>c','<.ctor>b__0_1'),
  @('RdcMan.SmartGroupPropertiesTabPage/<>c','<.ctor>b__1_0')
)){
  Add-BeforeRetCall (Find-Method $taskSpec[0] $taskSpec[1]) $taskCaption 'Translate smart-group rule dropdown captions without changing rule values or XML serialization'
}
$taskSessions=Find-Method 'RdcMan.ListSessionsForm' 'QuerySessions'
$taskStateCalls=@($taskSessions.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.TypeReference] -and $_.Operand.FullName -ceq 'Win32.Wts/ConnectstateClass' -and $_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Constrained})
if($taskStateCalls.Count -ne 1 -or $taskStateCalls[0].Next.Operand.Name -cne 'ToString'){throw 'Unexpected session status render site'}
$taskSessions.Body.GetILProcessor().InsertAfter($taskStateCalls[0].Next,[Mono.Cecil.Cil.Instruction]::Create($taskOps::Call,$taskCaption))
Add-Change $taskSessions 'Translate only the session-status label placed into list-view cells'
$taskMenu=Find-Method 'RdcMan.EnumMenuItem`1' '.ctor'
$taskMenuSet=@($taskMenu.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.FullName -ceq 'System.Void System.Windows.Forms.ToolStripItem::set_Text(System.String)'})
if($taskMenuSet.Count -ne 1){throw 'Unexpected enum menu constructor'}
$taskMenu.Body.GetILProcessor().InsertBefore($taskMenuSet[0],[Mono.Cecil.Cil.Instruction]::Create($taskOps::Call,$taskCaption))
Add-Change $taskMenu 'Translate display text of enum menu items; their Tag retains the original enum value'
Add-BeforeRetCall (Find-Method 'RdcMan.MainForm' 'get_DescriptionText') $taskCaption 'Use a Chinese product description for the window and About dialog without changing application identity'
$taskTitle=Find-Method 'RdcMan.MainForm' 'SetTitle'
$taskDescriptionCalls=@($taskTitle.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.FullName -ceq 'System.String RdcMan.MainForm::get_DescriptionText()'})
if($taskDescriptionCalls.Count -ne 1){throw 'Unexpected main-window title description site'}
$taskTitle.Body.GetILProcessor().InsertAfter($taskDescriptionCalls[0],[Mono.Cecil.Cil.Instruction]::Create($taskOps::Call,$taskTitleCaption))
Add-Change $taskTitle 'Keep the plain Chinese product name in the main title; the About dialog carries separate translation credit'

# Standard buttons default to 75 px, insufficient for a complete 5-digit size caption.
foreach($taskSpec in @(
  @('RdcMan.GlobalOptionsDialog','CreateClientAreaPage','_casCustomButton'),
  @('RdcMan.GlobalOptionsDialog','CreateClientAreaPage','_thumbnailPixelsButton'),
  @('RdcMan.RemoteDesktopTabPage','.ctor','_rdsCustomButton')
)){
  $taskM=Find-Method $taskSpec[0] $taskSpec[1]
  $taskStore=@($taskM.Body.Instructions | Where-Object {$_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Stfld -and $_.Operand.Name -ceq $taskSpec[2]})
  if($taskStore.Count -ne 1){throw 'Unexpected size-button field initialization'}
  $taskInsert=$taskStore[0]; $taskIl=$taskM.Body.GetILProcessor()
  foreach($taskNew in @(
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldarg_0),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldfld,$taskStore[0].Operand),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldc_I4,[int]132),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Callvirt,$taskControlSetWidth)
  )){ $taskIl.InsertAfter($taskInsert,$taskNew); $taskInsert=$taskNew }
  Add-Change $taskM ('Widen '+$taskSpec[2]+' to 132 logical pixels before DPI scaling')
}

# Resize translated labels before original layout reads their Right edges.
foreach($taskSpec in @(
  @('RdcMan.GlobalOptionsDialog','CreateClientAreaPage','_casCustomRadio',72),
  @('RdcMan.RemoteDesktopTabPage','.ctor','_rdsCustomRadio',72),
  @('RdcMan.GlobalOptionsDialog','CreateClientAreaPage','_thumbnailPixelsRadio',80),
  @('RdcMan.GlobalOptionsDialog','CreateClientAreaPage','_thumbnailPercentageRadio',88)
)){
  $taskM=Find-Method $taskSpec[0] $taskSpec[1]
  $taskFieldLoads=@($taskM.Body.Instructions | Where-Object {$_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldfld -and $_.Operand.Name -ceq $taskSpec[2] -and $_.Next.Operand -eq $taskSpec[3] -and $_.Next.Next.Operand -eq 24 -and $_.Next.Next.Next.Operand.FullName -ceq 'System.Void System.Drawing.Size::.ctor(System.Int32,System.Int32)'})
  if($taskFieldLoads.Count -ne 1){throw 'Unexpected custom-radio width initializer'}
  $taskFieldLoads[0].Next.OpCode=$taskOps::Ldc_I4
  $taskFieldLoads[0].Next.Operand=[int]110
  Add-Change $taskM ('Widen '+$taskSpec[2]+' to 110 logical pixels before original layout and DPI scaling')
}

# This fragment runs inside enhance-assembly.ps1 before scoped branch widening.
# All positions are logical pixels and are passed through the original DPI layout.
$taskAbout=Find-Method 'RdcMan.About' 'InitializeComponent'
$taskAboutWidths=@($taskAbout.Body.Instructions | Where-Object {$_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldc_I4 -and $_.Operand -eq 400})
if($taskAboutWidths.Count -ne 2){throw 'Unexpected About width initializers'}
foreach($taskAboutWidth in $taskAboutWidths){$taskAboutWidth.Operand=[int]560}
$taskAboutSize=@($taskAbout.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.FullName -ceq 'System.Void System.Windows.Forms.Form::set_ClientSize(System.Drawing.Size)'})
if($taskAboutSize.Count -ne 1 -or $taskAboutSize[0].Previous.Previous.Operand -ne 76){throw 'Unexpected About height initializer'}
$taskAboutSize[0].Previous.Previous.OpCode=$taskOps::Ldc_I4
$taskAboutSize[0].Previous.Previous.Operand=[int]162
$taskAboutPoints=@($taskAbout.Body.Instructions | Where-Object {$_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Newobj -and $_.Operand.FullName -ceq 'System.Void System.Drawing.Point::.ctor(System.Int32,System.Int32)'})
if($taskAboutPoints.Count -ne 5){throw 'Unexpected About control locations'}
foreach($taskPointSpec in @(@(0,53,13,64,18),@(1,53,29,64,46),@(2,53,45,64,74),@(4,10,10,16,18))){
  $taskAboutPoint=$taskAboutPoints[$taskPointSpec[0]]
  if($taskAboutPoint.Previous.Previous.Operand -ne $taskPointSpec[1] -or $taskAboutPoint.Previous.Operand -ne $taskPointSpec[2]){throw 'Unexpected About label or icon location'}
  $taskAboutPoint.Previous.Previous.OpCode=$taskOps::Ldc_I4
  $taskAboutPoint.Previous.Previous.Operand=[int]$taskPointSpec[3]
  $taskAboutPoint.Previous.OpCode=$taskOps::Ldc_I4
  $taskAboutPoint.Previous.Operand=[int]$taskPointSpec[4]
}
if($taskAboutPoints[3].Previous.Operand -ne 13){throw 'Unexpected About button top'}
$taskAboutPoints[3].Previous.OpCode=$taskOps::Ldc_I4
$taskAboutPoints[3].Previous.Operand=[int]126
# Add translation credit as a display-only label before original DPI layout.
# Reuse framework references already present in the original module.
function Find-AboutReference([string]$FullName){
  $taskMatches=@($taskAbout.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.FullName -ceq $FullName})
  if($taskMatches.Count -lt 1){throw ('Missing About framework reference: '+$FullName)}
  return $taskMatches[0].Operand
}
$taskAboutLabelCtor=Find-AboutReference 'System.Void System.Windows.Forms.Label::.ctor()'
$taskAboutPointCtor=Find-AboutReference 'System.Void System.Drawing.Point::.ctor(System.Int32,System.Int32)'
$taskAboutLocation=Find-AboutReference 'System.Void System.Windows.Forms.Control::set_Location(System.Drawing.Point)'
$taskAboutAutoSize=Find-AboutReference 'System.Void System.Windows.Forms.Control::set_AutoSize(System.Boolean)'
$taskAboutText=Find-AboutReference 'System.Void System.Windows.Forms.Control::set_Text(System.String)'
$taskAboutControls=Find-AboutReference 'System.Windows.Forms.Control/ControlCollection System.Windows.Forms.Control::get_Controls()'
$taskAboutAdd=Find-AboutReference 'System.Void System.Windows.Forms.Control/ControlCollection::Add(System.Windows.Forms.Control)'
$taskAboutScale=@($taskAbout.Body.Instructions | Where-Object {$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.FullName -ceq 'System.Void RdcMan.FormTools::ScaleAndLayout(System.Windows.Forms.Form)'})
if($taskAboutScale.Count -ne 1 -or $taskAboutScale[0].Previous.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldarg_0){throw 'Unexpected About scaling site'}
$taskAboutInsert=$taskAboutScale[0].Previous
$taskAboutIl=$taskAbout.Body.GetILProcessor()
foreach($taskCredit in (,@('汉化作者：kaixinit',102))){
  foreach($taskNew in @(
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldarg_0),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Call,$taskAboutControls),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Newobj,$taskAboutLabelCtor),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Dup),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldc_I4,[int]64),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldc_I4,[int]$taskCredit[1]),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Newobj,$taskAboutPointCtor),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Callvirt,$taskAboutLocation),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Dup),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldc_I4_1),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Callvirt,$taskAboutAutoSize),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Dup),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldstr,[string]$taskCredit[0]),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Callvirt,$taskAboutText),
    [Mono.Cecil.Cil.Instruction]::Create($taskOps::Callvirt,$taskAboutAdd)
  )){$taskAboutIl.InsertBefore($taskAboutInsert,$taskNew)}
}
Add-Change $taskAbout 'Use a 560 x 162 logical-pixel About layout with plain product title, software translation credit kaixinit, and OK below all text; preserve original DPI scaling'

# The original 2.93 range-expansion catch sets an error but leaves to success.
# Keep the dialog open on invalid input instead of passing a null result onward.
$taskImport=Find-Method 'RdcMan.ImportServersPropertiesPage' 'IsValid'
$taskImportCatch=@($taskImport.Body.ExceptionHandlers | Where-Object {
  $_.HandlerType -eq [Mono.Cecil.Cil.ExceptionHandlerType]::Catch -and
  $_.CatchType.FullName -ceq 'System.Exception' -and $_.HandlerStart.Offset -eq 327
})
if($taskImportCatch.Count -ne 1){throw 'Unexpected 2.93 import validation catch'}
$taskLeave=$taskImportCatch[0].HandlerEnd.Previous
if($taskLeave.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Leave -or
  $taskLeave.Operand.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldc_I4_1 -or
  $taskLeave.Operand.Next.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ret){throw 'Unexpected 2.93 import success return'}
$taskReject=[Mono.Cecil.Cil.Instruction]::Create($taskOps::Ldc_I4_0)
$taskImport.Body.GetILProcessor().Append($taskReject)
$taskImport.Body.GetILProcessor().Append([Mono.Cecil.Cil.Instruction]::Create($taskOps::Ret))
$taskLeave.Operand=$taskReject
Add-Change $taskImport 'Return false after a caught range validation error; preserve input and translated ErrorProvider while leaving the success path unchanged'

# Insertions can overflow original short branch encodings. Widen branches only in the scoped methods.
$taskLongBranches=@{Br_S='Br';Brfalse_S='Brfalse';Brtrue_S='Brtrue';Beq_S='Beq';Bge_S='Bge';Bge_Un_S='Bge_Un';Bgt_S='Bgt';Bgt_Un_S='Bgt_Un';Ble_S='Ble';Ble_Un_S='Ble_Un';Blt_S='Blt';Blt_Un_S='Blt_Un';Bne_Un_S='Bne_Un';Leave_S='Leave'}
foreach($taskName in $taskAllowed){
  foreach($taskI in $taskOriginalMethods[$taskName].Body.Instructions){
    $taskCode=$taskI.OpCode.Code.ToString()
    if($taskLongBranches.ContainsKey($taskCode)){$taskI.OpCode=$taskOps.GetField($taskLongBranches[$taskCode]).GetValue($null)}
  }
}
$taskOutput=Join-Path $taskRoot 'RDCMan.enhanced.exe'
$taskModule.Write($taskOutput); $taskModule.Dispose()
$taskReload=[Mono.Cecil.ModuleDefinition]::ReadModule($taskOutput)
$taskReloadMap=@{}
foreach($taskT in $taskReload.GetTypes()){foreach($taskM in $taskT.Methods){$taskReloadMap[$taskM.FullName]=$taskM}}
$taskUnchanged=0
foreach($taskT in $taskBase.GetTypes()){
  foreach($taskM in $taskT.Methods){
    if($taskAllowed.Contains($taskM.FullName)){continue}
    $taskN=$taskReloadMap[$taskM.FullName]
    if($null -eq $taskN -or $taskN.HasBody -ne $taskM.HasBody){throw 'Unexpected method change'}
    if($taskM.HasBody){
      if($taskM.Body.Instructions.Count -ne $taskN.Body.Instructions.Count){throw ('Unexpected instruction count: '+$taskM.FullName)}
      for($taskI=0;$taskI -lt $taskM.Body.Instructions.Count;$taskI++){
        if($taskM.Body.Instructions[$taskI].ToString() -cne $taskN.Body.Instructions[$taskI].ToString()){throw ('Unexpected instruction change: '+$taskM.FullName)}
      }
    }
    $taskUnchanged++
  }
}
if(($taskBase.AssemblyReferences.FullName -join '|') -cne ($taskReload.AssemblyReferences.FullName -join '|')){throw 'Dependency changed'}
$taskBaseResource=@{}; foreach($taskR in $taskBase.Resources){if($taskR -is [Mono.Cecil.EmbeddedResource]){$taskBaseResource[$taskR.Name]=(Get-BytesSHA256 $taskR.GetResourceData())}}
foreach($taskR in $taskReload.Resources){if($taskR -is [Mono.Cecil.EmbeddedResource]){if($taskBaseResource[$taskR.Name] -cne (Get-BytesSHA256 $taskR.GetResourceData())){throw 'Resource changed'}}}
$taskReload.Dispose(); $taskBase.Dispose()
Copy-Item -LiteralPath $taskOutput -Destination $taskInput -Force
$taskReport=Get-Content -LiteralPath (Join-Path $taskRoot 'assembly-verification.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskReport | Add-Member -NotePropertyName 'BaseTranslationOnlyVerification' -NotePropertyValue $taskReport.OnlyApprovedStringOperandsChanged -Force
$taskReport.OnlyApprovedStringOperandsChanged=$false
$taskReport | Add-Member -NotePropertyName 'ScopedUiEnhancements' -NotePropertyValue @($taskChanges) -Force
$taskReport | Add-Member -NotePropertyName 'UnchangedMethodsAfterUiEnhancements' -NotePropertyValue $taskUnchanged -Force
$taskReport | Add-Member -NotePropertyName 'AddedPureUiHelperMethods' -NotePropertyValue 4 -Force
$taskReport.LocalizedAssemblySHA256=(Get-FileHash -LiteralPath $taskInput).Hash
$taskReport | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $taskRoot 'assembly-verification.json') -Encoding utf8
@{UiEnhancements=@($taskChanges);UnchangedMethods=$taskUnchanged;CanonicalPairs=$taskCanonicalPairs;CaptionPairs=$taskCaptionPairs;LocalizedAssemblySHA256=$taskReport.LocalizedAssemblySHA256} | ConvertTo-Json -Depth 6

