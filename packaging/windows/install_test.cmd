@echo off
REM Installs -- or uninstalls -- the built MSI and reports the exit code. Run from anywhere:
REM
REM     cmd /c "E:\hollow-court\packaging\windows\install_test.cmd"
REM     cmd /c "E:\hollow-court\packaging\windows\install_test.cmd" uninstall
REM
REM **Why a file and not a line in a shell.** Every attempt to hand msiexec this package
REM through git-bash or PowerShell produced a mangled command line, because the path
REM contains a space and each shell quoted it differently -- `\"` came through literally
REM from bash, and PowerShell's -ArgumentList joined the array with spaces and added no
REM quotes at all. msiexec then received `/i E:\Hollow` and sat waiting on an error box
REM nobody could see: no log, no files, and no exit code. That was read for two rounds as
REM "msiexec hangs on this host". A batch file has no shell in the middle to misquote.
REM
REM **The uninstall half exists because a reinstall needs it.** While every build carried the same
REM package version, installing over an existing install was a same-version upgrade, which msiexec
REM answers with error 1638 rather than a repair -- so the uninstall half was the only way to reinstall,
REM and also the only way that path ever got exercised at all.
REM
REM **That changed on 2026-09-23, and the change is the interesting test.** Rounds now carry versions
REM (1.0.0, then 1.0.514), so `install` over an older install is a real MajorUpgrade: msiexec replaces
REM the old product rather than answering 1638. Both behaviours belong in this script's history, so
REM both are written down: an upgrade is expected now, and a 1638 means somebody built two packages
REM with the same version again.
setlocal
set ACTION=%~1
if "%ACTION%"=="" set ACTION=install
set MSI=%~2
REM **The default is the NEWEST package in the bundle, not a written-down name.** It used to name
REM `hollow-court-1.0.0.msi` literally, which is the same staleness this round is fixing everywhere else:
REM after the version changed, the default would have installed the previous build while the log, the
REM receipt and the person reading it all said "the current one".
REM
REM `/o:n` is ASCENDING by name and the loop keeps the last line it sees, so the winner is the
REM alphabetically last -- and `1.0.0.msi` sorts before `1.0.514.msi`, which is the order wanted.
REM The first version of this line used `/o-n`, descending, so it picked the OLDEST package and
REM promptly answered 1638 (same version already installed) -- a bug that happened to look like the
REM very behaviour it was written to avoid.
if "%MSI%"=="" for /f "delims=" %%f in ('dir /b /o:n "E:\Hollow Court Bundle\hollow-court-*.msi" 2^>nul') do set MSI=E:\Hollow Court Bundle\%%f
if "%MSI%"=="" set MSI=E:\Hollow Court Bundle\hollow-court-1.0.514.msi
set LOG=%~3
if "%LOG%"=="" set LOG=E:\DaShaoHuo\cache\msi-%ACTION%.log

echo action : %ACTION%
echo package: "%MSI%"
echo log    : "%LOG%"
if /I "%ACTION%"=="uninstall" (
  msiexec /x "%MSI%" /qn /norestart /l*v "%LOG%"
) else (
  msiexec /i "%MSI%" /qn /norestart /l*v "%LOG%"
)
echo exit=%ERRORLEVEL%
endlocal
