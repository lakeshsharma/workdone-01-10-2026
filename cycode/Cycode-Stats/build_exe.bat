@echo off
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo Creating local virtual environment .venv ...
    py -m venv .venv
    ".venv\Scripts\python.exe" -m pip install --quiet --upgrade pip
)

echo Installing/updating build dependencies into .venv (isolated - never touches your system Python) ...
".venv\Scripts\python.exe" -m pip install --quiet -r requirements.txt

echo.
echo Building Cycode-Stats.exe (this bundles the Cycode CLI itself, so the
echo result needs nothing pre-installed on the machine it runs on) ...
".venv\Scripts\python.exe" -m PyInstaller --noconfirm --onefile --windowed --name Cycode-Stats ^
    --collect-all cycode ^
    --collect-all typer ^
    --collect-all click ^
    --collect-all rich ^
    main.py

echo.
echo Done. Standalone exe is at dist\Cycode-Stats.exe
echo Share just that one file - nothing else needs installing on the target machine.
pause
