@echo off
REM Aggregate ONLY Data.mdb under F:\Evolution\File\1 into ONE CSV (ordered by ID)

"C:\Users\XS\AppData\Local\Programs\Python\Python314\python.exe" ^
  "C:\LabTools\py\mdb_to_csv_aggregate.py" ^
  --base "F:\Evolution\File\1" ^
  -o "C:\LabTools\output_csv" ^
  --pc-name "ComputerA" ^
  --order-by ID ^
  --file-name "Data.mdb"
