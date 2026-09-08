// 現在のWindowsユーザーのアプリ管理ファイルだけを扱う。
// 署名鍵、共有ランタイム、利用者が作成した別名ファイルは対象外。
const
  ReparsePointAttribute = $400;
var
  DataPage: TInputOptionWizardPage;
  DeleteUserData: Boolean;
  DataChangeFailed: Boolean;

function OcoFileAttributes(Name: String): Cardinal;
  external 'GetFileAttributesW@kernel32.dll stdcall';

function DataBase: String;
begin
  #ifdef OcoTestDataRoot
  Result := '{#OcoTestDataRoot}';
  #else
  Result := ExpandConstant('{userappdata}');
  #endif
end;

function DataRoot(Legacy: Boolean): String;
begin
  Result := DataBase + '\jp.nononoyuyuyu\';
  if Legacy then Result := Result + 'OC運営用総合ツール'
  else Result := Result + 'Open Campus Organizer';
end;

function DataDirectory(Legacy: Boolean): String;
begin
  Result := DataRoot(Legacy);
  if Legacy then Result := Result + '\oc_operations\v1'
  else Result := Result + '\open_campus_organizer\v1';
end;

function ManagedDataFile(Name: String): Boolean;
var
  I, Dot: Integer;
  Extension: String;
begin
  Result := False;
  Dot := Pos('.', Name);
  if Dot < 2 then Exit;
  Extension := Copy(Name, Dot, Length(Name));
  if (Extension <> '.data') and (Extension <> '.csv') and
     (Extension <> '.data.tmp') and (Extension <> '.csv.tmp') and
     (Extension <> '.data.migration.tmp') and (Extension <> '.csv.migration.tmp') then Exit;
  for I := 1 to Dot - 1 do
    if not (((Name[I] >= 'a') and (Name[I] <= 'z')) or
      ((Name[I] >= '0') and (Name[I] <= '9')) or (Name[I] = '_')) then Exit;
  Result := True;
end;

function HasUserData: Boolean;
var
  Legacy: Integer;
  Find: TFindRec;
begin
  Result := False;
  for Legacy := 0 to 1 do begin
    if FileExists(DataRoot(Legacy = 1) + '\flutter_secure_storage.dat') then begin Result := True; Exit; end;
    if FindFirst(DataDirectory(Legacy = 1) + '\*', Find) then begin
      try
        repeat
          if ManagedDataFile(Find.Name) then begin Result := True; Exit; end;
        until not FindNext(Find);
      finally FindClose(Find); end;
    end;
  end;
end;

procedure RequireSafeDataPath(Path: String);
var
  Current, Parent: String;
begin
  // 別の場所を指すジャンクション・シンボリックリンクをたどらない。
  Current := ExpandFileName(Path);
  if Pos(Lowercase(AddBackslash(ExpandFileName(DataBase))), Lowercase(Current)) <> 1 then
    RaiseException('データの保存先が想定した範囲外です。');
  while Length(Current) > 3 do begin
    if (OcoFileAttributes(Current) <> $FFFFFFFF) and
       ((OcoFileAttributes(Current) and ReparsePointAttribute) <> 0) then
      RaiseException('データの保存先がリンクになっているため変更しません。');
    Parent := ExtractFileDir(Current);
    if Parent = Current then Break;
    Current := Parent;
  end;
end;

procedure ClearUserData;
var
  Files: TStringList;
  Legacy, I: Integer;
  Folder, Credential: String;
  Find: TFindRec;
begin
  Files := TStringList.Create;
  try
    // 一件も削除する前に、全候補の絶対パスとリンク属性を確認する。
    for Legacy := 0 to 1 do begin
      Folder := DataDirectory(Legacy = 1);
      RequireSafeDataPath(Folder);
      Credential := DataRoot(Legacy = 1) + '\flutter_secure_storage.dat';
      RequireSafeDataPath(Credential);
      if FileExists(Credential) then Files.Add(Credential);
      if FindFirst(Folder + '\*', Find) then begin
        try
          repeat
            if ManagedDataFile(Find.Name) then begin
              RequireSafeDataPath(Folder + '\' + Find.Name);
              if (Find.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then Files.Add(Folder + '\' + Find.Name);
            end;
          until not FindNext(Find);
        finally FindClose(Find); end;
      end;
    end;
    // 旧版の保存済みToken・設定を次回起動で再取り込みしない。
    RequireSafeDataPath(DataRoot(False) + '\.oco_storage_migrated_v1');
    if not ForceDirectories(DataRoot(False)) or
       not SaveStringToFile(DataRoot(False) + '\.oco_storage_migrated_v1', '1', False) then
      RaiseException('データ初期化の準備に失敗しました。');
    for I := 0 to Files.Count - 1 do begin
      RequireSafeDataPath(Files[I]);
      if not DeleteFile(Files[I]) then RaiseException('設定・履歴の一部を削除できませんでした。');
    end;
    Log('OCO: user data selection applied.');
  finally Files.Free; end;
end;

procedure InitializeWizard;
begin
  DataPage := CreateInputOptionPage(wpSelectDir, '保存済みデータ',
    '前回の設定・履歴を引き継ぎますか？',
    '新しく始める場合、このWindowsユーザーの設定・履歴・保存済みToken・再開待ちの処理を削除します。', True, False);
  DataPage.Add('前回のデータを引き継ぐ');
  DataPage.Add('データを削除して新しく始める');
  DataPage.SelectedValueIndex := 0;
  if Lowercase(ExpandConstant('{param:DATA|keep}')) = 'reset' then DataPage.SelectedValueIndex := 1;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = DataPage.ID) and not HasUserData;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and (DataPage.SelectedValueIndex = 1) then begin
    try ClearUserData;
    except
      DataChangeFailed := True;
      SuppressibleMsgBox(GetExceptionMessage, mbError, MB_OK, IDOK);
    end;
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  if DataChangeFailed then Result := 20 else Result := 0;
end;

function InitializeUninstall: Boolean;
var Choice: Integer;
begin
  Result := True;
  DeleteUserData := Lowercase(ExpandConstant('{param:DATA|keep}')) = 'delete';
  if not UninstallSilent and HasUserData then begin
    Choice := MsgBox('設定・履歴・保存済みTokenを残しますか？' + #13#10 +
      '「はい」: 次回のインストールで引き継げます。' + #13#10 +
      '「いいえ」: 再開待ちの処理を含めて削除します。', mbConfirmation, MB_YESNOCANCEL or MB_DEFBUTTON1);
    Result := Choice <> IDCANCEL;
    DeleteUserData := Choice = IDNO;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and DeleteUserData then begin
    try ClearUserData;
    except SuppressibleMsgBox(GetExceptionMessage, mbError, MB_OK, IDOK); end;
  end;
end;
