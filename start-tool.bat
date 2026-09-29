@echo off
chcp 65001 >nul
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0send-gui.ps1"
