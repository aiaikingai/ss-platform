from pathlib import Path
from labtool.split_and_delta import split_and_build_delta

result = split_and_build_delta(
    Path(r'C:\SSLab\MDR_PC_01\ALL_Values.csv'),
    Path(r'C:\SSLab\MDR_PC_01\source_id.txt'),
    Path(r'C:\SSLab\MDR_PC_01\out')
)
print(result)
```

---

**Step 6 — Save and close Notepad**

Press **Ctrl+S** to save, then close the Notepad window.

---

**Step 7 — Come back to PowerShell and tell me**

Your prompt should still show:
```
(.venv) PS C:\Users\XS\Projects\ss-lab-platform>