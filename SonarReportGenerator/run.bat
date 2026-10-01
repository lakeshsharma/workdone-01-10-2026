@echo off
REM ============================================================
REM  One-click run from source.
REM  Double-click this file, or run it from cmd/PowerShell.
REM  First run installs dependencies, then launches the GUI.
REM ============================================================
cd /d "%~dp0"
where python >nul 2>&1 || (echo [ERROR] Python not found on PATH. Install Python 3.10+ first. & pause & exit /b 1)
python -c "import requests, openpyxl, win32com.client" 2>nul || (
  echo Installing dependencies, please wait...
  python -m pip install -r requirements.txt
)
python main.py
if errorlevel 1 pause
