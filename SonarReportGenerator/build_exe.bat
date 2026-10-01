@echo off
REM Build a single-file Windows .exe. Run once; produces dist\SonarVulnReporter.exe
cd /d "%~dp0"
python -m pip install -r requirements.txt
python -m PyInstaller --noconfirm --onefile --windowed ^
  --name SonarVulnReporter ^
  --add-data "data;data" ^
  --hidden-import win32com --hidden-import win32com.client ^
  --collect-submodules win32com ^
  main.py
echo.
echo Built: dist\SonarVulnReporter.exe
echo (Keep the data\ folder next to the exe, or it is bundled read-only inside.)
pause
