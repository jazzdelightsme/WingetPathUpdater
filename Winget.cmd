@ECHO off
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

REM This wrapper script is a straight "pass-through" to winget.exe, and then after running
REM an install, it will update your in-process PATH environment variable.

REM The following line is important for the installer script:
REM This file is part of the WingetPathUpdater package.

IF "%1" == "install" (
    SET TheHelperCommand=powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command . %~dp0wingetHelper.ps1 ; StoreStaticPathFromRegistry
    FOR /F "tokens=* USEBACKQ" %%i IN (`!TheHelperCommand!`) DO (
        SET StaticPathBefore=%%i
    )
    REM ECHO StaticPathBefore is: !StaticPathBefore!
)

winget.exe %*

IF NOT "%StaticPathBefore%" == "" (

    SET TheHelperCommand=powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command . %~dp0wingetHelper.ps1 ; GenerateAdditionsCmd \"%PSModulePath%\" \"%StaticPathBefore%\"

    FOR /F "tokens=* USEBACKQ" %%i IN (`!TheHelperCommand!`) DO (
        SET ScriptToUpdateEnvironment=%%i
    )
    REM ECHO ScriptToUpdateEnvironment is: !ScriptToUpdateEnvironment!

    del "%StaticPathBefore%"
)

IF NOT "%ScriptToUpdateEnvironment%" == "" (
    REM ECHO Updating local environment block
    ENDLOCAL & CALL %ScriptToUpdateEnvironment% & del %ScriptToUpdateEnvironment%
)
