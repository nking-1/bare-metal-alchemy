@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" arm64 >nul 2>&1

echo === Building sieve demo ===
pushd sieve
armasm64 -nologo sieve.asm -o sieve.obj
if errorlevel 1 goto :fail
cl /nologo /O2 sieve_main.c sieve.obj /Fe:primes.exe
if errorlevel 1 goto :fail
popd

echo === Building NEON demo ===
pushd neon_uppercase
armasm64 -nologo neon_upper.asm -o neon_upper.obj
if errorlevel 1 goto :fail
cl /nologo /O2 neon_main.c neon_upper.obj /Fe:neon_demo.exe
if errorlevel 1 goto :fail
popd

echo === All builds succeeded ===
goto :eof
:fail
echo --- BUILD FAILED ---
exit /b 1
