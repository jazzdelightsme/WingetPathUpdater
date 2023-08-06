@ECHO off
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

REM This wrapper script is a straight "pass-through" to winget.exe, and then after running
REM an install, it will update your in-process PATH environment variable.

REM This file is part of the WingetPathUpdater package.

IF "%1" == "install" (
    SET TheHelperCommand=powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command . %~dp0wingetHelper.ps1 ; GetStaticPathFromRegistry PATH
    FOR /F "tokens=* USEBACKQ" %%i IN (`!TheHelperCommand!`) DO (
        SET StaticPathBefore=%%i
    )
)

winget.exe %*

IF NOT "%StaticPathBefore%" == "" (
    FOR /F "tokens=* USEBACKQ" %%i IN (`!TheHelperCommand!`) DO (
        SET StaticPathAfter=%%i
    )

    SET TheHelperCommand=powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command . %~dp0wingetHelper.ps1 ; CalculateAdditions 'PATH' '%StaticPathBefore%' '!StaticPathAfter!'

    FOR /F "tokens=* USEBACKQ" %%i IN (`!TheHelperCommand!`) DO (
        SET Additions=%%i
    )
    REM ECHO Additions are: !Additions!
)

IF NOT "%Additions%" == "" (
    ENDLOCAL & SET PATH=%PATH%;%Additions%
)
