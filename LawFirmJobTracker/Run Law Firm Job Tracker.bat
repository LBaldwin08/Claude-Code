@echo off
title Law Firm Library & Research Job Tracker
echo =====================================================
echo  Law Firm Library ^& Research Job Tracker
echo  Searching for library/research jobs at top firms...
echo =====================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0law_firm_jobs.ps1"
echo.
echo Press any key to close...
pause > nul
