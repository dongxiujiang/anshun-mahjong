Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

!ifndef ReleaseVersion
  !define ReleaseVersion "1.2.0"
!endif
!define Root "${__FILEDIR__}\..\.."
Name "安顺麻将·捉鸡"
OutFile "${Root}\build\releases\v${ReleaseVersion}\anshun-mahjong-setup-${ReleaseVersion}.exe"
InstallDir "$LOCALAPPDATA\Programs\AnshunMahjong"
InstallDirRegKey HKCU "Software\AnshunMahjong" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
Icon "${Root}\res\icons\game_icon.ico"
UninstallIcon "${Root}\res\icons\game_icon.ico"
VIProductVersion "${ReleaseVersion}.0"
VIAddVersionKey /LANG=2052 "ProductName" "安顺麻将·捉鸡安装程序"
VIAddVersionKey /LANG=2052 "FileDescription" "安顺麻将 Windows 安装程序"
VIAddVersionKey /LANG=2052 "FileVersion" "${ReleaseVersion}"
VIAddVersionKey /LANG=2052 "ProductVersion" "${ReleaseVersion}"
VIAddVersionKey /LANG=2052 "LegalCopyright" "东秀麻将"

!define MUI_ABORTWARNING
!define MUI_ICON "${Root}\res\icons\game_icon.ico"
!define MUI_UNICON "${Root}\res\icons\game_icon.ico"
!define MUI_WELCOMEPAGE_TITLE "欢迎安装安顺麻将"
!define MUI_WELCOMEPAGE_TEXT "安装 Windows 版安顺麻将。支持横屏牌桌、局域网房间和游戏内小版本更新。$\r$\n$\r$\n安装到当前用户目录，无需管理员权限。"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\安顺麻将.exe"
!define MUI_FINISHPAGE_RUN_TEXT "启动安顺麻将"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

Var IsTest
Var Parameters
Function .onInit
  SetShellVarContext current
  StrCpy $IsTest "0"
  ${GetParameters} $Parameters
  ClearErrors
  ${GetOptions} $Parameters "/TEST" $0
  ${IfNot} ${Errors}
    StrCpy $IsTest "1"
  ${EndIf}
FunctionEnd

Section "安装游戏"
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File "${Root}\build\windows\安顺麻将.exe"
  File "${Root}\build\releases\v${ReleaseVersion}\用户说明.txt"
  WriteUninstaller "$INSTDIR\卸载安顺麻将.exe"
  ${If} $IsTest == "1"
    FileOpen $0 "$INSTDIR\.installation-test" w
    FileClose $0
  ${Else}
    WriteRegStr HKCU "Software\AnshunMahjong" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AnshunMahjong" "DisplayName" "安顺麻将·捉鸡"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AnshunMahjong" "DisplayVersion" "${ReleaseVersion}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AnshunMahjong" "Publisher" "东秀麻将"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AnshunMahjong" "UninstallString" '$\"$INSTDIR\卸载安顺麻将.exe$\"'
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AnshunMahjong" "DisplayIcon" "$INSTDIR\安顺麻将.exe"
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AnshunMahjong" "NoModify" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AnshunMahjong" "NoRepair" 1
    CreateDirectory "$SMPROGRAMS\安顺麻将"
    CreateShortcut "$SMPROGRAMS\安顺麻将\安顺麻将.lnk" "$INSTDIR\安顺麻将.exe"
    CreateShortcut "$DESKTOP\安顺麻将.lnk" "$INSTDIR\安顺麻将.exe"
  ${EndIf}
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  IfFileExists "$INSTDIR\.installation-test" skip_registration
  ReadRegStr $0 HKCU "Software\AnshunMahjong" "InstallDir"
  ${If} $0 == $INSTDIR
    DeleteRegKey HKCU "Software\AnshunMahjong"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AnshunMahjong"
    Delete "$DESKTOP\安顺麻将.lnk"
    Delete "$SMPROGRAMS\安顺麻将\安顺麻将.lnk"
    RMDir "$SMPROGRAMS\安顺麻将"
  ${EndIf}
  skip_registration:
  Delete "$INSTDIR\.installation-test"
  Delete "$INSTDIR\安顺麻将.exe"
  Delete "$INSTDIR\安顺麻将.exe.previous"
  Delete "$INSTDIR\用户说明.txt"
  Delete "$INSTDIR\卸载安顺麻将.exe"
  RMDir "$INSTDIR"
SectionEnd
