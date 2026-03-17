@echo off
setlocal

cd /d C:\Users\XS\Projects\ss-lab-platform

call .venv\Scripts\activate

python scripts\windows\run_labtool_pipeline.py

endlocal