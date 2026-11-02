@echo off
cd /d "%~dp0"
py -3 server.py %*
if errorlevel 1 (
  echo Service stopped with an error. Read the message above; ensure the complete ZIP was extracted.
  pause
)
