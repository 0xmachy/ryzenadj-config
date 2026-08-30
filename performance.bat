@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: script ini harus dijalankan sebagai Administrator.
    echo Klik kanan file ini, pilih "Run as administrator".
    pause
    exit /b 1
)

set "RYZENADJ=C:\Users\Administrator\Documents\ryzenadj-win64\ryzenadj.exe"

if not exist %RYZENADJ% (
    echo Error: ryzenadj.exe tidak ditemukan di %RYZENADJ%
    pause
    exit /b 1
)

echo == Menerapkan power limit 25W ke AMD 3020e via ryzenadj ==
%RYZENADJ% ^
  --stapm-limit=25000 ^
  --fast-limit=28000 ^
  --slow-limit=25000 ^
  --stapm-time=300 ^
  --slow-time=90 ^
  --tctl-temp=90 ^
  --vrm-current=30000 ^
  --vrmsoc-current=20000 ^
  --vrmmax-current=40000 ^
  --vrmsocmax-current=25000 ^
  --psi0-current=5000 ^
  --psi0soc-current=5000 ^
  --max-socclk-frequency=1200 ^
  --min-socclk-frequency=400 ^
  --max-fclk-frequency=1200 ^
  --min-fclk-frequency=400 ^
  --max-vcn=1100 ^
  --max-lclk=1200 ^
  --min-lclk=400 ^
  --max-gfxclk=1300 ^
  --min-gfxclk=200 ^
  --prochot-deassertion-ramp=10 ^
  -i

echo.
echo == Selesai ==
pause