@echo off
chcp 65001 >nul 2>&1
rem ===========================================================================
rem  proj-sync 설치 마법사 (그래픽 창) 실행용 런처
rem  ---------------------------------------------------------------------------
rem  이 파일을 "더블클릭" 하면 install-gui.ps1 (WinForms GUI)이 창으로 열립니다.
rem  · 그래픽 창이 안 뜨면 같은 폴더의 "윈도우-원터치설치.bat"(검은 콘솔)을 쓰세요.
rem ===========================================================================

if not exist "%~dp0install-gui.ps1" (
  echo.
  echo    !  install-gui.ps1 을 찾지 못했습니다.
  echo       이 .bat 파일과 install-gui.ps1 이 "같은 폴더"에 있어야 합니다.
  echo.
  pause
  exit /b 1
)

rem  -STA : WinForms 필수  /  -ExecutionPolicy Bypass : 서명 없는 스크립트 허용
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0install-gui.ps1"

if errorlevel 1 (
  echo.
  echo    !  그래픽 창 실행에 실패했습니다.
  echo       같은 폴더의  "윈도우-원터치설치.bat"  ^(검은 콘솔^) 로 설치하세요.
  echo.
  pause
)
exit /b
