@echo off
:: ==============================================
::  Fulbito Downloader - Launcher para Windows
:: ==============================================
::
::  Uso:
::    descargar_fulbito.bat
::    descargar_fulbito.bat -Nombre "fulbo_martes"
::    descargar_fulbito.bat -Fecha "2026-07-06" -Horas "21,22"
::
::  Primera vez: descarga ffmpeg automaticamente (~90MB).
::

title Fulbito Downloader

:: Obtener directorio del script
set "SCRIPT_DIR=%~dp0"

:: Ejecutar PowerShell con bypass de politica (solo para este script)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%sportsreel_download.ps1" %*

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Hubo un error. Presiona una tecla para cerrar.
    pause > nul
) else (
    echo.
    echo Presiona una tecla para cerrar.
    pause > nul
)
