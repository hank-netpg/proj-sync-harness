@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
title proj-sync 원터치 설치
color 0F

rem ===========================================================================
rem  proj-sync 원터치 설치 (Windows 전용)
rem  ---------------------------------------------------------------------------
rem  이 파일을 "더블클릭" 하면:
rem    1) Git · VS Code · Python · GitHub CLI · Claude Code 가 깔려 있는지 확인
rem    2) 없는 것만 자동으로 설치
rem    3) 마지막에 proj-sync 플러그인까지 설치
rem  까지 한 번에 진행합니다.
rem  여러 번 실행해도 안전합니다 (이미 깔린 건 건너뜁니다).
rem ===========================================================================

set "NEED_RESTART=0"

echo.
echo  ============================================================
echo    proj-sync 원터치 설치를 시작합니다
echo  ============================================================
echo.
echo    이 창은 "필요한 프로그램"을 자동으로 깔아줍니다.
echo    설치 도중  [ 이 앱이 기기를 변경하도록 허용하시겠습니까? ]
echo    창이 뜨면  반드시  " 예(Y) "  를 눌러 주세요.
echo.
echo    ※ 인터넷이 연결돼 있어야 합니다. 10~20분 걸릴 수 있어요.
echo.
pause

rem ---------------------------------------------------------------------------
rem  0) winget(윈도우 자동설치 도구) 있는지 확인
rem ---------------------------------------------------------------------------
echo.
echo  [0/6] 자동 설치 도구(winget) 확인 중...
set "HAVE_WINGET=1"
where winget >nul 2>&1
if errorlevel 1 (
  set "HAVE_WINGET=0"
  echo.
  echo    !  이 컴퓨터에는 winget^(윈도우 자동설치 도구^)이 없습니다.
  echo       구형 Windows·기업 관리 PC 등에서 흔한 경우입니다.
  echo       → 멈추지 않고, 공식 홈페이지에서 "직접 다운로드" 방식으로
  echo         설치를 이어서 진행합니다. ^(인터넷 연결 필요^)
  echo.
) else (
  echo         OK - winget 사용 가능
)

rem ---------------------------------------------------------------------------
rem  1) Git for Windows  (git·curl·unzip·Git Bash·Git LFS 포함)
rem ---------------------------------------------------------------------------
echo.
echo  [1/6] Git for Windows 확인 중...
call :ENSURE "Git.Git" "git" "Git for Windows"

rem ---------------------------------------------------------------------------
rem  2) VS Code (코드 편집기 / 터미널)
rem ---------------------------------------------------------------------------
echo.
echo  [2/6] VS Code 확인 중...
call :ENSURE "Microsoft.VisualStudioCode" "code" "VS Code"

rem ---------------------------------------------------------------------------
rem  3) Python (파일 분류 등 내부 처리에 사용)
rem ---------------------------------------------------------------------------
echo.
echo  [3/6] Python 확인 중...
where python >nul 2>&1
if not errorlevel 1 (
  echo         OK - 이미 설치됨: Python
) else (
  where py >nul 2>&1
  if not errorlevel 1 (
    echo         OK - 이미 설치됨: Python
  ) else (
    echo         설치를 시작합니다: Python  ^(허용 창이 뜨면 예^)
    if "%HAVE_WINGET%"=="1" (
      winget install --id Python.Python.3.12 -e --source winget --accept-package-agreements --accept-source-agreements
    ) else (
      call :DIRECT_python
    )
    set "NEED_RESTART=1"
  )
)

rem ---------------------------------------------------------------------------
rem  4) GitHub CLI (권장 - GitHub 로그인/동기화 편의)
rem ---------------------------------------------------------------------------
echo.
echo  [4/6] GitHub CLI 확인 중... ^(권장^)
call :ENSURE_OPTIONAL "GitHub.cli" "gh" "GitHub CLI"

rem ---------------------------------------------------------------------------
rem  5) Claude Code (핵심 - 이 도구가 있어야 플러그인이 동작)
rem ---------------------------------------------------------------------------
echo.
echo  [5/6] Claude Code 확인 중...
where claude >nul 2>&1
if not errorlevel 1 (
  echo         OK - 이미 설치됨: Claude Code
) else (
  echo         설치를 시작합니다: Claude Code
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
  set "NEED_RESTART=1"
)

rem ---------------------------------------------------------------------------
rem  PATH 새로고침 (방금 깐 프로그램을 이 창에서 바로 인식하도록)
rem ---------------------------------------------------------------------------
call :REFRESH_PATH

rem ---------------------------------------------------------------------------
rem  6) proj-sync 플러그인 설치
rem ---------------------------------------------------------------------------
echo.
echo  [6/6] proj-sync 플러그인 설치 준비 중...

rem  Claude Code 가 이번에 새로 깔렸다면 PATH 반영을 위해 재실행이 필요할 수 있음
where claude >nul 2>&1
if errorlevel 1 (
  echo.
  echo    !  방금 Claude Code 를 새로 설치했습니다.
  echo       이 창을 "닫았다가" 이 파일을 "다시 더블클릭" 하면
  echo       플러그인 설치까지 자동으로 마무리됩니다.
  echo.
  goto :END
)

rem  Git Bash(bash.exe) 위치 찾기
set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "BASH=%LocalAppData%\Programs\Git\bin\bash.exe"
rem  where bash 폴백 - 단, C:\Windows\System32\bash.exe 는 WSL 런처이므로 제외
rem  (WSL 스텁을 실행하면 "설치된 배포가 없습니다" WSL 안내가 잘못 뜸)
if not defined BASH (
  for /f "delims=" %%B in ('where bash 2^>nul') do (
    if not defined BASH (
      echo %%B| findstr /i /c:"\System32\" >nul || set "BASH=%%B"
    )
  )
)
if not defined BASH (
  echo.
  echo    !  Git Bash 를 찾지 못했습니다. Git 설치가 끝난 뒤
  echo       이 창을 닫고 이 파일을 다시 더블클릭해 주세요.
  echo.
  goto :END
)

rem  플러그인 본체(install.sh) 폴더 찾기 - 배포본(proj-sync) 또는 레포(plugin)
set "PLUGDIR="
if exist "%~dp0proj-sync\install.sh" set "PLUGDIR=%~dp0proj-sync"
if not defined PLUGDIR if exist "%~dp0plugin\install.sh" set "PLUGDIR=%~dp0plugin"

rem  정보 입력 스크립트 찾기 - 배포본(proj-sync-setup.sh) 또는 레포(src/..)
rem  Git Bash 에 넘길 때 경로 오해가 없도록 "상대경로(슬래시)" 로 보관
set "SETUP="
if exist "%~dp0proj-sync-setup.sh" set "SETUP=proj-sync-setup.sh"
if not defined SETUP if exist "%~dp0src\proj-sync-onboard.sh" set "SETUP=src/proj-sync-onboard.sh"

if not defined PLUGDIR if not defined SETUP (
  echo.
  echo    !  설치 파일(proj-sync-setup.sh)을 찾지 못했습니다.
  echo       압축을 올바르게 풀었는지 확인하세요.
  echo       ^(이 .bat 파일은 proj-sync-setup.sh 와 "같은 폴더"에 있어야 합니다^)
  echo.
  goto :END
)

echo.
echo  ------------------------------------------------------------
echo    프로그램 설치가 끝났습니다.
echo    이어서 "나만의 정보 입력"^(GitHub 토큰 / Slack / 본인 이름 등^)까지
echo    지금 바로 진행할 수 있습니다.
echo  ------------------------------------------------------------
echo.
echo      Y = 지금 이어서 입력 ^(권장^)       N = 나중에 직접 할게요
echo.
set "GO="
set /p "GO=지금 이어서 하시겠어요? (Y/N) [Y]: "
if /I "%GO%"=="N" goto :INSTALL_ONLY
if not defined SETUP goto :INSTALL_ONLY

rem  --- 정보 입력까지 이어서: proj-sync-setup.sh 실행 ---
rem  (setup 은 실행 첫 단계에서 플러그인 설치까지 스스로 수행합니다)
echo.
echo    잠시 후  "무엇을 할까요?"  메뉴가 나오면
echo      · 지금 입력하려면  숫자  1  을 누르고 Enter
echo      · 나중에 하려면     q  를 누르고 Enter
echo.
pushd "%~dp0"
"%BASH%" "%SETUP%"
popd
echo.
echo  ============================================================
echo    모두 끝났습니다!  수고하셨어요.
echo  ============================================================
echo.
echo    마지막으로  Claude Code^(또는 VS Code^)를 "껐다 켜면"
echo    채팅창에서  /ax  명령들이 보입니다.
echo.
goto :END

:INSTALL_ONLY
rem  --- 플러그인만 설치하고, 정보 입력은 나중에 ---
if defined PLUGDIR (
  echo.
  echo         플러그인을 설치합니다...
  pushd "%PLUGDIR%"
  "%BASH%" install.sh
  set "RC=%ERRORLEVEL%"
  popd
  if not "!RC!"=="0" (
    echo.
    echo    !  플러그인 설치 중 문제가 있었습니다. 이 파일을 한 번 더 실행해 보세요.
    goto :END
  )
)
echo.
echo  ============================================================
echo    프로그램 설치 완료!  정보 입력만 남았어요.
echo  ============================================================
echo.
echo    나중에 아래 순서로 정보^(토큰/이름^)를 입력하세요:
echo      1^) Claude Code^(또는 VS Code^) 껐다 켜기
echo      2^) VS Code 에서 이 폴더 열기 ^(File - Open Folder^)
echo      3^) 터미널에 아래 한 줄 붙여넣고 Enter:
echo.
echo           bash proj-sync-setup.sh
echo.
echo    자세한 방법은  "무작정따라하기.md"  문서를 보세요.
echo.
goto :END


rem ===========================================================================
rem  함수들
rem ===========================================================================

:ENSURE
rem  %~1 = winget ID, %~2 = 확인용 명령, %~3 = 표시 이름  (필수 - 실패 시 안내)
where %~2 >nul 2>&1
if not errorlevel 1 (
  echo         OK - 이미 설치됨: %~3
  exit /b 0
)
echo         설치를 시작합니다: %~3  ^(허용 창이 뜨면 예^)
if "%HAVE_WINGET%"=="1" (
  winget install --id %~1 -e --source winget --accept-package-agreements --accept-source-agreements
) else (
  call :DIRECT_%~2
)
set "NEED_RESTART=1"
exit /b 0

:ENSURE_OPTIONAL
rem  권장 도구 - 설치 실패해도 계속 진행
where %~2 >nul 2>&1
if not errorlevel 1 (
  echo         OK - 이미 설치됨: %~3
  exit /b 0
)
echo         설치를 시도합니다: %~3  ^(실패해도 계속 진행^)
if "%HAVE_WINGET%"=="1" (
  winget install --id %~1 -e --source winget --accept-package-agreements --accept-source-agreements
) else (
  call :DIRECT_%~2
)
exit /b 0

:REFRESH_PATH
rem  레지스트리에서 최신 PATH 를 다시 읽어 이 창에 반영
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')"`) do set "PATH=%%P"
exit /b 0

rem ===========================================================================
rem  직접 다운로드 설치 (winget 이 없는 PC 용 폴백)
rem  - 다운로드는 PowerShell 로 수행 (모든 Windows 기본 내장, curl 유무 무관)
rem  - Git·GitHub CLI 는 GitHub API 로 "최신 버전" 을 자동 해석 (버전 안 늙음)
rem ===========================================================================

:DOWNLOAD
rem  %~1 = 다운로드 URL, %~2 = 저장 경로  (성공 0 / 실패 1)
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -UseBasicParsing -Uri '%~1' -OutFile '%~2' } catch { exit 1 }"
exit /b %errorlevel%

:DIRECT_git
rem  Git for Windows - GitHub 릴리스에서 최신 64bit 설치 파일 자동 해석
set "OUT=%TEMP%\proj-sync-git.exe"
echo         Git 설치 파일 다운로드 중...  ^(수십 MB, 잠시만요^)
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { $r=Invoke-RestMethod -UseBasicParsing -Headers @{'User-Agent'='proj-sync'} 'https://api.github.com/repos/git-for-windows/git/releases/latest'; $u=($r.assets | Where-Object { $_.name -like '*-64-bit.exe' } | Select-Object -First 1).browser_download_url; Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%OUT%' } catch { exit 1 }"
if errorlevel 1 (
  echo         X  Git 다운로드 실패 - 인터넷 확인 후 다시 시도하세요.
  echo            수동 설치: https://git-scm.com/download/win
  exit /b 1
)
echo         Git 설치 중...  ^(허용 창이 뜨면 예^)
"%OUT%" /VERYSILENT /NORESTART /SP- /SUPPRESSMSGBOXES /NOCANCEL
del "%OUT%" >nul 2>&1
exit /b 0

:DIRECT_code
rem  VS Code - 공식 stable 리다이렉트 URL (항상 최신 사용자 설치본)
set "OUT=%TEMP%\proj-sync-vscode.exe"
echo         VS Code 다운로드 중...
call :DOWNLOAD "https://update.code.visualstudio.com/latest/win32-x64-user/stable" "%OUT%"
if errorlevel 1 (
  echo         X  VS Code 다운로드 실패 - 수동 설치: https://code.visualstudio.com
  exit /b 1
)
echo         VS Code 설치 중...
"%OUT%" /VERYSILENT /NORESTART /MERGETASKS=addcontextmenufiles,addcontextmenufolders,addtopath
del "%OUT%" >nul 2>&1
exit /b 0

:DIRECT_python
rem  Python 3.12 - python.org 공식 배포본 (사용자 설치 + PATH 추가)
set "OUT=%TEMP%\proj-sync-python.exe"
echo         Python 다운로드 중...
call :DOWNLOAD "https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe" "%OUT%"
if errorlevel 1 (
  echo         X  Python 다운로드 실패 - 수동 설치: https://www.python.org/downloads
  echo            ^(설치 시 "Add python.exe to PATH" 체크^)
  exit /b 1
)
echo         Python 설치 중...
"%OUT%" /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1
del "%OUT%" >nul 2>&1
exit /b 0

:DIRECT_gh
rem  GitHub CLI - GitHub 릴리스에서 최신 windows amd64 MSI 자동 해석 (선택 도구)
set "OUT=%TEMP%\proj-sync-gh.msi"
echo         GitHub CLI 다운로드 중...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { $r=Invoke-RestMethod -UseBasicParsing -Headers @{'User-Agent'='proj-sync'} 'https://api.github.com/repos/cli/cli/releases/latest'; $u=($r.assets | Where-Object { $_.name -like '*windows_amd64.msi' } | Select-Object -First 1).browser_download_url; Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%OUT%' } catch { exit 1 }"
if errorlevel 1 (
  echo         -  GitHub CLI 다운로드 실패 ^(선택 도구라 건너뜁니다^)
  exit /b 0
)
echo         GitHub CLI 설치 중...
msiexec /i "%OUT%" /quiet /norestart
del "%OUT%" >nul 2>&1
exit /b 0

:END
echo.
echo  ------------------------------------------------------------
echo    창을 닫으려면 아무 키나 누르세요.
echo  ------------------------------------------------------------
pause >nul
endlocal
exit /b
