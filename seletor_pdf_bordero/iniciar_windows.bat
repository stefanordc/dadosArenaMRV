@echo off
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (start "" "http://127.0.0.1:8765" & py -3 servidor.py & goto :eof)
where python >nul 2>nul
if %errorlevel%==0 (start "" "http://127.0.0.1:8765" & python servidor.py & goto :eof)
echo Python 3 nao encontrado. Instale Python 3 em https://www.python.org/downloads/
pause
