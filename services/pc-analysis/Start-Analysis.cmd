@echo off
cd /d "%~dp0"
py -3 server.py
if errorlevel 1 (
  echo Install Python 3.11 or later with the Windows Python launcher, then try again.
  pause
)
