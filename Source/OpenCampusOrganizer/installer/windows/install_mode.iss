// 同一AppId・同一保存先はInno Setupの更新としてアンインストール記録を継続する。
function ExistingInstallError(RootKey: HKEY; OtherMode: Boolean): String;
var PreviousDir: String;
begin
  Result := '';
  if RegQueryStringValue(RootKey,
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{D4EBAB8B-0A55-489B-A9E1-BF65C0C96CD4}_is1',
    'InstallLocation', PreviousDir) and
    FileExists(AddBackslash(PreviousDir) + 'unins000.exe') then begin
    if OtherMode then begin
      Log('OCO: blocked different install scope.');
      if RootKey = HKCU then
        Result := '既存のアプリは現在のユーザー向けです。全ユーザー向けの指定を外して更新してください。'
      else
        Result := '既存のアプリは全ユーザー向けです。全ユーザー向けのインストーラーとして更新してください。';
      Result := Result + #13#10 + 'インストール対象を変更する場合は、先に既存のアプリをアンインストールしてください。';
    end else if CompareText(RemoveBackslashUnlessRoot(PreviousDir), RemoveBackslashUnlessRoot(WizardDirValue)) <> 0 then begin
      Log('OCO: blocked different install directory.');
      Result := '既存のインストールを更新する場合は、次のフォルダーを選択してください。' + #13#10 +
        PreviousDir + #13#10 + '保存先を変更する場合は、先に既存のアプリをアンインストールしてください。設定と履歴は引き継げます。';
    end;
  end;
end;

function SelectedInstallError: String;
begin
  // コマンドラインの/ALLUSERS・/CURRENTUSERでも反対側の登録を見落とさない。
  Result := ExistingInstallError(HKCU, IsAdminInstallMode);
  if Result = '' then Result := ExistingInstallError(HKLM64, not IsAdminInstallMode);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var ErrorText: String;
begin
  Result := True;
  if CurPageID = wpSelectDir then begin
    ErrorText := SelectedInstallError;
    Result := ErrorText = '';
    if not Result then SuppressibleMsgBox(ErrorText, mbError, MB_OK, IDOK);
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var Version: String;
begin
  Result := '';
  if GetVersionNumbersString(AddBackslash(WizardDirValue) + 'open_campus_organizer.exe', Version) then
    Result := '既存のアプリを更新します（' + Version + ' → {#AppVersion}）。' + NewLine + NewLine;
  Result := Result + MemoDirInfo + NewLine + NewLine + MemoGroupInfo;
  if MemoTasksInfo <> '' then Result := Result + NewLine + NewLine + MemoTasksInfo;
end;

function IsLegacyStartMenuShortcut: Boolean;
var Shell, Link: Variant;
begin
  Result := False;
  if not FileExists(ExpandConstant('{autoprograms}\Open Campus Organizer.lnk')) then Exit;
  try
    Shell := CreateOleObject('WScript.Shell');
    Link := Shell.CreateShortcut(ExpandConstant('{autoprograms}\Open Campus Organizer.lnk'));
    Result := CompareText(Link.TargetPath, ExpandConstant('{app}\open_campus_organizer.exe')) = 0;
  except
    Log('OCO: legacy shortcut could not be inspected; keeping it.');
  end;
end;
