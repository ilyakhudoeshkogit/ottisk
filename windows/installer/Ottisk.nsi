; Установщик «Оттиск» — один файл, без прав администратора, ставит в профиль пользователя.
Unicode true
!ifndef VERSION
  !define VERSION "0.6.0"
!endif
!ifndef EXE
  !define EXE "..\dist\publish\Ottisk.exe"
!endif
!ifndef OUTFILE
  !define OUTFILE "..\dist\Ottisk-Setup-${VERSION}.exe"
!endif

!define APPNAME "Оттиск"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Ottisk"

Name "${APPNAME} ${VERSION}"
OutFile "${OUTFILE}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\Ottisk"
InstallDirRegKey HKCU "Software\Ottisk" "InstallDir"
SetCompressor /SOLID lzma
SetCompressorDictSize 32
BrandingText "Оттиск ${VERSION}"
ShowInstDetails nevershow
ShowUnInstDetails nevershow

VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1049 "ProductName" "Оттиск"
VIAddVersionKey /LANG=1049 "FileDescription" "Установка программы печати Оттиск"
VIAddVersionKey /LANG=1049 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1049 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1049 "LegalCopyright" "© Ilya Khudoeshko"

!include "MUI2.nsh"
!define MUI_ICON "..\src\Ottisk.App\Assets\ottisk.ico"
!define MUI_UNICON "..\src\Ottisk.App\Assets\ottisk.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\Ottisk.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Запустить Оттиск"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Russian"

Function .onInit
  ; Если программа запущена, файл заменить нельзя — просим закрыть.
  retry:
  ClearErrors
  IfFileExists "$INSTDIR\Ottisk.exe" 0 done
  FileOpen $0 "$INSTDIR\Ottisk.exe" a
  IfErrors 0 closeit
  MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Оттиск сейчас открыт. Закройте его и нажмите «Повторить»." IDRETRY retry
  Abort
  closeit:
  FileClose $0
  done:
FunctionEnd

Section "Оттиск"
  SetOutPath "$INSTDIR"
  File "${EXE}"
  File "..\src\Ottisk.App\Assets\ottisk.ico"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Ярлыки: рабочий стол и меню «Пуск»
  CreateShortcut "$DESKTOP\Оттиск.lnk" "$INSTDIR\Ottisk.exe" "" "$INSTDIR\ottisk.ico"
  CreateShortcut "$SMPROGRAMS\Оттиск.lnk" "$INSTDIR\Ottisk.exe" "" "$INSTDIR\ottisk.ico"

  ; «Открыть с помощью» для PDF и картинок (необязательно, только для этого пользователя)
  WriteRegStr HKCU "Software\Classes\Applications\Ottisk.exe\shell\open\command" "" '"$INSTDIR\Ottisk.exe" "%1"'
  WriteRegStr HKCU "Software\Classes\Applications\Ottisk.exe" "FriendlyAppName" "Оттиск"
  WriteRegStr HKCU "Software\Classes\Applications\Ottisk.exe\SupportedTypes" ".pdf" ""
  WriteRegStr HKCU "Software\Classes\Applications\Ottisk.exe\SupportedTypes" ".jpg" ""
  WriteRegStr HKCU "Software\Classes\Applications\Ottisk.exe\SupportedTypes" ".jpeg" ""
  WriteRegStr HKCU "Software\Classes\Applications\Ottisk.exe\SupportedTypes" ".png" ""

  ; Запись в «Приложения» (Параметры → Приложения)
  WriteRegStr HKCU "Software\Ottisk" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayName" "Оттиск"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTKEY}" "Publisher" "Ottisk"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\ottisk.ico"
  WriteRegStr HKCU "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\Оттиск.lnk"
  Delete "$SMPROGRAMS\Оттиск.lnk"
  Delete "$INSTDIR\Ottisk.exe"
  Delete "$INSTDIR\ottisk.ico"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Classes\Applications\Ottisk.exe"
  DeleteRegKey HKCU "${UNINSTKEY}"
  DeleteRegKey HKCU "Software\Ottisk"
  ; Настройки в %APPDATA%\Ottisk остаются — они ничего не весят.
SectionEnd
