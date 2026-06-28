@echo off
REM Levanta el server de las tools (rigtool / Hechizos / Wall / AoE) y abre el navegador.
REM Doble clic para usar. Cerra la ventana del server para pararlo.
cd /d "%~dp0.."
start "Cuteos Tools (:8765)" cmd /k "py tools\serve.py || python tools\serve.py"
timeout /t 2 /nobreak >nul
start "" http://localhost:8765/tools/
