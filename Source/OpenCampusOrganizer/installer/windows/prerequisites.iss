// 共有ランタイムはアンインストール時に削除しない。
const
  RuntimeKey = 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';

var
  RuntimeRestartRequired: Boolean;

function RuntimeVersionIsCompatible(Major, Minor, Build, Revision: Cardinal): Boolean;
begin
  if Major <> {#VcRuntimeMajor} then
    Result := Major > {#VcRuntimeMajor}
  else if Minor <> {#VcRuntimeMinor} then
    Result := Minor > {#VcRuntimeMinor}
  else if Build <> {#VcRuntimeBuild} then
    Result := Build > {#VcRuntimeBuild}
  else
    Result := Revision >= {#VcRuntimeRevision};
end;

function RuntimePresentInView(RootKey: HKEY): Boolean;
var
  Installed, Major, Minor, Build, Revision: Cardinal;
begin
  Result := RegQueryDWordValue(RootKey, RuntimeKey, 'Installed', Installed) and
    (Installed = 1) and
    RegQueryDWordValue(RootKey, RuntimeKey, 'Major', Major) and
    RegQueryDWordValue(RootKey, RuntimeKey, 'Minor', Minor) and
    RegQueryDWordValue(RootKey, RuntimeKey, 'Bld', Build) and
    RegQueryDWordValue(RootKey, RuntimeKey, 'Rbld', Revision);
  if Result then
    Result := RuntimeVersionIsCompatible(Major, Minor, Build, Revision);
end;

function RuntimeIsInstalled: Boolean;
begin
  Result := RuntimePresentInView(HKLM64) or RuntimePresentInView(HKLM32);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  RuntimePath, Arguments: String;
  ResultCode: Integer;
  Started: Boolean;
begin
  Result := SelectedInstallError;
  if Result <> '' then Exit;
  if RuntimeIsInstalled then begin
    Log('OCO: compatible Visual C++ x64 runtime is already installed.');
    Exit;
  end;

  ExtractTemporaryFile('vc_redist.x64.exe');
  RuntimePath := ExpandConstant('{tmp}\vc_redist.x64.exe');
  Arguments := '/install /quiet /norestart /log "' +
    ExpandConstant('{tmp}\OpenCampusOrganizer-vc-runtime.log') + '"';
  WizardForm.StatusLabel.Caption := '必要な実行環境をインストールしています…';

  if IsAdmin then
    Started := Exec(RuntimePath, Arguments, '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  else
    Started := ShellExec('runas', RuntimePath, Arguments, '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);

  Log(Format('OCO: runtime installer started=%d, result=%d', [Ord(Started), ResultCode]));
  if not Started then begin
    Result := '実行環境をインストールできませんでした。Windowsの確認画面で許可してから、もう一度実行してください。';
    Exit;
  end;

  // 3010は成功・再起動待ち。既存の新しいバージョンとの競合は再検出して判断する。
  if (ResultCode <> 0) and (ResultCode <> 3010) and (ResultCode <> 1638) then begin
    Result := Format('実行環境のインストールに失敗しました（コード %d）。他のインストールが完了してから、もう一度実行してください。', [ResultCode]);
    Exit;
  end;
  if not RuntimeIsInstalled then begin
    NeedsRestart := ResultCode = 3010;
    Result := '必要な実行環境を確認できませんでした。Windowsを再起動してから、インストーラーをもう一度実行してください。';
    Exit;
  end;
  RuntimeRestartRequired := ResultCode = 3010;
end;

function NeedRestart: Boolean;
begin
  Result := RuntimeRestartRequired;
end;

function CanLaunchApplication: Boolean;
begin
  Result := not RuntimeRestartRequired and not DataChangeFailed;
end;
