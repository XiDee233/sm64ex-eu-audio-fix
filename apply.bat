@echo off
setlocal
rem ============================================================
rem  One-click apply: eu-audio-fix.patch  ->  sm64ex source tree
rem
rem  Usage:
rem    apply.bat "D:\path\to\sm64ex"     (or drag the sm64ex folder onto this file)
rem    apply.bat                         (assumes .\..\sm64ex next to this script)
rem
rem  Safe: dry-runs first, refuses to touch anything if it would
rem  not apply cleanly, and detects an already-patched tree.
rem ============================================================

set "PATCH=%~dp0eu-audio-fix.patch"
set "SRC=%~1"
if "%SRC%"=="" set "SRC=%~dp0..\sm64ex"

if not exist "%PATCH%" goto :nopatch
if not exist "%SRC%\Makefile" goto :nosrc

where git >nul 2>nul
if errorlevel 1 goto :nogit

pushd "%SRC%"

git apply --check "%PATCH%" 2>nul
if not errorlevel 1 goto :doapply

git apply --check --reverse "%PATCH%" 2>nul
if not errorlevel 1 goto :already

popd
echo [x] The patch does not apply cleanly.
echo     This tree is probably not upstream "nightly", or it already
echo     carries a different EU audio fix.
echo     Nothing was modified.
pause
exit /b 1

:doapply
git apply "%PATCH%"
if errorlevel 1 goto :failed
echo [+] Applied successfully.
echo       Makefile            - VERSION_ASFLAGS no longer clobbers VERSION_EU
echo       src/audio/port_eu.c - added #include "heap.h"
echo.
echo     Undo:    git apply --reverse "%PATCH%"
echo     Rebuild: make VERSION=eu WINDOWS_BUILD=1
popd
pause
exit /b 0

:failed
popd
echo [x] git apply failed halfway. Inspect the tree before rebuilding.
echo     Undo: git apply --reverse "%PATCH%"
pause
exit /b 1

:already
echo [i] Already applied - nothing to do.
popd
pause
exit /b 0

:nogit
echo [x] git was not found in PATH. Install Git for Windows, or apply
echo     the patch manually with: patch -p1 ^< eu-audio-fix.patch
pause
exit /b 1

:nosrc
echo [x] Not an sm64ex source tree: "%SRC%"
echo     Expected to find "Makefile" in it.
echo     Usage: apply.bat "D:\path\to\sm64ex"
pause
exit /b 1

:nopatch
echo [x] Patch file not found next to this script: "%PATCH%"
pause
exit /b 1
