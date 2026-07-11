@echo off
setlocal

echo Đang tien hanh gop cac ky nang (abilities) thanh ability_all.lua...
echo ----------------------------------------------------

:: Xoa file cu
if exist "..\Scripts\ability_all.lua" del "..\Scripts\ability_all.lua"

:: Gop file bang PowerShell (xu ly an toan UTF-8 va xuong dong)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$files = Get-Content 'ability_order.txt' | Where-Object { $_.Trim() -ne '' }; if ($files) { Get-Content $files | Set-Content '..\Scripts\ability_all.lua' -Encoding UTF8 }"

echo ----------------------------------------------------
echo Gop file hoan tat! Kiem tra ability_all.lua nhe.
