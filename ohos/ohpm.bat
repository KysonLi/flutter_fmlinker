@echo off
rem Workaround: DevEco's ohpm.bat recurses (Windows batch stack overflow) when
rem invoked by Flutter/Dart Process.runSync, crashing `flutter build hap` at
rem `ohpm clean`. This shadow calls pm-cli.js directly. It must appear in PATH
rem before DevEco's ohpm.bat (Flutter sets NoDefaultCurrentDirectoryInExePath,
rem so CWD shadowing does not work).
set "OHPM_BIN=%DEVECO_SDK_HOME:~0,-4%\tools\ohpm\bin"
if not exist "%OHPM_BIN%\pm-cli.js" set "OHPM_BIN=C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin"
node "%OHPM_BIN%\pm-cli.js" %*
exit /b %errorlevel%
