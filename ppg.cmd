@echo off
rem PPG Movie Streamer entry point for cmd and PowerShell. Example: ppg install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ppg.ps1" %*
