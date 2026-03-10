@echo off
REM Aggregate ONLY Data.mdb under F:\Evolution\File\1 into ONE canonical ALL_Values.csv

"C:\Users\XS\AppData\Local\Programs\Python\Python314\python.exe" ^
  "C:\Users\XS\Projects\ss-lab-platform\src\labtool\extract_aggregate_mdb.py" ^
  --base "F:\Evolution\File\1" ^
  -o "C:\SSLab\MDR_PC_01" ^
  --pc-name "MDR_PC_01" ^
  --order-by ID ^
  --file-name "Data.mdb" ^
  --temp-copy-dir "C:\SSLab\temp_mdb_copy"