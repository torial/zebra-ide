; zebra-ide Windows installer (Inno Setup 6). Built by .github/workflows/build.yml:
;
;   iscc /DAppVersion=0.1.0 /DSourceExe=...\app.exe /DRepoDir=... /DOutputDir=dist
;        /DOutputBase=zebra-ide-0.1.0-windows-x86_64-setup packaging\windows\zebra-ide.iss
;
; What it does: installs zebra-ide.exe (per-user by default; "all users" when run elevated
; or with /ALLUSERS), a Start-menu entry, an uninstaller, and -- as a task, on by default --
; the install folder on PATH, because the IDE takes its PROJECT ROOT from the directory it
; is started in: `cd myproject` then `zebra-ide`. The Start-menu entry starts in Documents.
;
; It does NOT install Zebra. The IDE needs `zebra` on PATH at run time; the finish page
; says so when it cannot find one (on PATH or in %USERPROFILE%\.zebra\current, where the
; Zebra installer puts it).
;
; No icon: the repository has no application icon yet, and a made-up one would be worse
; than Windows' default.

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
#ifndef SourceExe
  #error SourceExe (the built app.exe) must be defined: /DSourceExe=...
#endif
#ifndef RepoDir
  #error RepoDir (the repository root, for README.md and INSTALL.txt) must be defined
#endif
#ifndef OutputDir
  #define OutputDir "dist"
#endif
#ifndef OutputBase
  #define OutputBase "zebra-ide-setup"
#endif

[Setup]
AppId={{6F1E2B7C-9C2D-4C61-9E0A-5B4F7D3A2E18}
AppName=zebra-ide
AppVersion={#AppVersion}
AppVerName=zebra-ide {#AppVersion}
AppPublisher=torial
AppPublisherURL=https://github.com/torial/zebra-ide
AppSupportURL=https://github.com/torial/zebra-ide/issues
DefaultDirName={autopf}\zebra-ide
DefaultGroupName=zebra-ide
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesEnvironment=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBase}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=zebra-ide {#AppVersion}

[Tasks]
Name: "addtopath"; Description: "Add zebra-ide to PATH, so ""zebra-ide"" can be started from a project folder"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#SourceExe}"; DestDir: "{app}"; DestName: "zebra-ide.exe"; Flags: ignoreversion
Source: "{#RepoDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoDir}\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\zebra-ide"; Filename: "{app}\zebra-ide.exe"; WorkingDir: "{userdocs}"
Name: "{autoprograms}\zebra-ide README"; Filename: "{app}\README.md"
Name: "{autodesktop}\zebra-ide"; Filename: "{app}\zebra-ide.exe"; WorkingDir: "{userdocs}"; Tasks: desktopicon

[Code]
// PATH lives under HKCU\Environment for a per-user install and under HKLM's Session
// Manager key for an all-users one; IsAdminInstallMode says which this is, in both the
// installer and the uninstaller.
function EnvRoot: Integer;
begin
  if IsAdminInstallMode then Result := HKEY_LOCAL_MACHINE else Result := HKEY_CURRENT_USER;
end;

function EnvKey: String;
begin
  if IsAdminInstallMode then
    Result := 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
  else
    Result := 'Environment';
end;

procedure AddToPath(Dir: String);
var
  P: String;
begin
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', P) then P := '';
  if Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(P) + ';') > 0 then Exit;
  if (P <> '') and (P[Length(P)] <> ';') then P := P + ';';
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', P + Dir);
end;

// Removes exactly the entry AddToPath wrote, wherever it now sits; leaves PATH untouched
// when the entry is not there.
procedure RemoveFromPath(Dir: String);
var
  P, W: String;
  I: Integer;
begin
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', P) then Exit;
  W := ';' + P + ';';
  I := Pos(';' + Uppercase(Dir) + ';', Uppercase(W));
  if I = 0 then Exit;
  Delete(W, I, Length(Dir) + 1);
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', Copy(W, 2, Length(W) - 2));
end;

function ZebraFound: Boolean;
begin
  Result := (FileSearch('zebra.exe', GetEnv('PATH')) <> '') or
            FileExists(ExpandConstant('{%USERPROFILE}\.zebra\current\zebra.exe'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('addtopath') then
    AddToPath(ExpandConstant('{app}'));
  if (CurStep = ssPostInstall) and not ZebraFound then
    Log('zebra.exe not found on PATH or in %USERPROFILE%\.zebra\current');
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and not ZebraFound then
    WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 +
      'The Zebra compiler was not found. zebra-ide needs "zebra" on PATH to check, build ' +
      'and run code; install it from https://github.com/torial/zebra-language#install';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemoveFromPath(ExpandConstant('{app}'));
end;
