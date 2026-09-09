# ===========================================================================
#  proj-sync 설치 마법사 (GUI) — Windows 내장 PowerShell + WinForms
#  ---------------------------------------------------------------------------
#  · 추가 런타임 설치 불필요 (Windows 10/11 기본 포함)
#  · 하는 일: Git·VS Code·Python·GitHub CLI·Claude Code 설치 → 진행바로 표시
#            → 완료 후 "지금 이어서 입력 / 나중에" 선택
#  · 토큰·이름 입력(대화형)은 검증된 기존 콘솔(proj-sync-setup.sh)이 이어받습니다.
#  ⚠ 이 파일은 직접 더블클릭하지 말고, "윈도우-설치(그래픽).bat" 으로 실행하세요.
# ===========================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

# ── 스레드 공유 상태 (백그라운드 설치 ↔ UI) ───────────────────────────────
$sync = [hashtable]::Synchronized(@{})
$sync.Log      = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$sync.Progress = 0
$sync.Status   = "준비되었습니다. [설치 시작] 을 눌러 주세요."
$sync.Done     = $false
$sync.Success  = $false

# ── 도우미: bash / 플러그인·설치 스크립트 위치 찾기 ───────────────────────
function Get-BashPath {
  $cands = @("$env:ProgramFiles\Git\bin\bash.exe",
             "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
             "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  $g = Get-Command bash -ErrorAction SilentlyContinue
  if ($g) { return $g.Source }
  return $null
}
function Get-PluginDir {
  foreach ($d in @("$scriptDir\proj-sync", "$scriptDir\plugin")) {
    if (Test-Path "$d\install.sh") { return $d }
  }
  return $null
}
function Get-SetupRel {
  if (Test-Path "$scriptDir\proj-sync-setup.sh")      { return "proj-sync-setup.sh" }
  if (Test-Path "$scriptDir\src\proj-sync-onboard.sh"){ return "src/proj-sync-onboard.sh" }
  return $null
}

# ── 백그라운드에서 실제 설치를 수행하는 작업 블록 ─────────────────────────
$work = {
  param($sync)
  function Log($m) { $sync.Log.Enqueue([string]$m) }
  function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
  function Ensure($id, $cmd, $name, $optional) {
    if (Have $cmd) { Log "  OK - 이미 설치됨: $name"; return }
    Log "  설치 시작: $name  (허용 창이 뜨면 '예')"
    try {
      winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements | Out-Null
    } catch { Log "  ! $name 설치 중 문제: $($_.Exception.Message)" }
    if (Have $cmd) { Log "  OK - 설치 완료: $name" }
    elseif (-not $optional) { Log "  … $name 은 창을 다시 실행하면 인식됩니다." }
  }

  # winget 확인
  $sync.Status = "자동 설치 도구(winget) 확인 중..."; $sync.Progress = 3
  if (-not (Have winget)) {
    Log "  X  이 컴퓨터에는 winget 이 없습니다."
    Log "     Microsoft Store 에서 '앱 설치 관리자' 를 설치하거나,"
    Log "     git-scm.com · code.visualstudio.com · python.org · claude.ai/code 에서"
    Log "     직접 설치한 뒤 이 창을 다시 실행하세요."
    $sync.Success = $false; $sync.Done = $true; return
  }

  $sync.Status = "[1/6] Git for Windows 확인 중...";  $sync.Progress = 8
  Ensure "Git.Git" "git" "Git for Windows" $false ;   $sync.Progress = 20

  $sync.Status = "[2/6] VS Code 확인 중...";           $sync.Progress = 24
  Ensure "Microsoft.VisualStudioCode" "code" "VS Code" $false ; $sync.Progress = 38

  $sync.Status = "[3/6] Python 확인 중...";            $sync.Progress = 42
  if ((Have python) -or (Have py)) { Log "  OK - 이미 설치됨: Python" }
  else { Ensure "Python.Python.3.12" "python" "Python" $false }
  $sync.Progress = 55

  $sync.Status = "[4/6] GitHub CLI 확인 중... (권장)"; $sync.Progress = 58
  Ensure "GitHub.cli" "gh" "GitHub CLI" $true ;        $sync.Progress = 66

  $sync.Status = "[5/6] Claude Code 확인 중...";       $sync.Progress = 70
  if (Have claude) { Log "  OK - 이미 설치됨: Claude Code" }
  else {
    Log "  설치 시작: Claude Code"
    try {
      $installer = Invoke-RestMethod -UseBasicParsing "https://claude.ai/install.ps1"
      Invoke-Expression $installer
      Log "  OK - Claude Code 설치 시도 완료"
    } catch { Log "  ! Claude 자동 설치 실패: https://claude.ai/code 에서 직접 설치하세요." }
  }
  $sync.Progress = 90

  $sync.Status = "[6/6] 마무리 중...";                 $sync.Progress = 96
  # 이 프로세스의 PATH 를 최신으로 (이후 실행할 bash 자식이 claude 를 찾도록)
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
  Log ""
  Log "  프로그램 설치가 끝났습니다."
  $sync.Progress = 100
  $sync.Success  = $true
  $sync.Done     = $true
}

# ── 폼(창) 만들기 ─────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = "proj-sync 설치 마법사"
$form.Font            = New-Object System.Drawing.Font("맑은 고딕", 9)
$form.ClientSize      = New-Object System.Drawing.Size(560, 470)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.MinimizeBox     = $true

$title = New-Object System.Windows.Forms.Label
$title.Text     = "프로젝트 동기화 도구 설치"
$title.Font     = New-Object System.Drawing.Font("맑은 고딕", 15, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 18)
$form.Controls.Add($title)

$desc = New-Object System.Windows.Forms.Label
$desc.Text     = "필요한 프로그램(Git·VS Code·Python·Claude 등)을 자동으로 설치합니다.`r`n설치 중 '허용하시겠습니까?' 창이 뜨면 반드시 [예] 를 눌러 주세요."
$desc.AutoSize = $true
$desc.Location = New-Object System.Drawing.Point(22, 54)
$form.Controls.Add($desc)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text     = "▶  설치 시작"
$btnStart.Font     = New-Object System.Drawing.Font("맑은 고딕", 12, [System.Drawing.FontStyle]::Bold)
$btnStart.Size     = New-Object System.Drawing.Size(200, 46)
$btnStart.Location = New-Object System.Drawing.Point(180, 100)
$form.Controls.Add($btnStart)

$status = New-Object System.Windows.Forms.Label
$status.Text     = $sync.Status
$status.AutoSize = $false
$status.Size     = New-Object System.Drawing.Size(520, 20)
$status.Location = New-Object System.Drawing.Point(22, 160)
$form.Controls.Add($status)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Size     = New-Object System.Drawing.Size(516, 22)
$progress.Location = New-Object System.Drawing.Point(22, 184)
$progress.Minimum  = 0
$progress.Maximum  = 100
$form.Controls.Add($progress)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline  = $true
$log.ReadOnly   = $true
$log.ScrollBars = "Vertical"
$log.BackColor  = [System.Drawing.Color]::FromArgb(30, 30, 30)
$log.ForeColor  = [System.Drawing.Color]::Gainsboro
$log.Font       = New-Object System.Drawing.Font("맑은 고딕", 9)
$log.Size       = New-Object System.Drawing.Size(516, 180)
$log.Location   = New-Object System.Drawing.Point(22, 216)
$form.Controls.Add($log)

# 완료 후 버튼들 (처음엔 숨김)
$btnNow = New-Object System.Windows.Forms.Button
$btnNow.Text     = "지금 이어서 정보 입력 (권장)"
$btnNow.Size     = New-Object System.Drawing.Size(250, 40)
$btnNow.Location = New-Object System.Drawing.Point(22, 410)
$btnNow.Visible  = $false
$form.Controls.Add($btnNow)

$btnLater = New-Object System.Windows.Forms.Button
$btnLater.Text     = "나중에 (플러그인만 설치)"
$btnLater.Size     = New-Object System.Drawing.Size(200, 40)
$btnLater.Location = New-Object System.Drawing.Point(286, 410)
$btnLater.Visible  = $false
$form.Controls.Add($btnLater)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text     = "닫기"
$btnClose.Size     = New-Object System.Drawing.Size(120, 40)
$btnClose.Location = New-Object System.Drawing.Point(418, 410)
$btnClose.Visible  = $false
$form.Controls.Add($btnClose)

# ── 진행 상황을 주기적으로 UI 에 반영하는 타이머 ──────────────────────────
$script:finalized = $false
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 150
$timer.Add_Tick({
  while ($sync.Log.Count -gt 0) { $log.AppendText([string]$sync.Log.Dequeue() + "`r`n") }
  $p = [int]$sync.Progress
  if ($p -ge 0 -and $p -le 100) { $progress.Value = $p }
  $status.Text = [string]$sync.Status

  if ($sync.Done -and -not $script:finalized) {
    $script:finalized = $true
    $timer.Stop()
    # 자식 프로세스(bash)가 방금 깐 claude 를 찾도록 PATH 갱신
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    if ($sync.Success) {
      $status.Text     = "설치 완료! 이어서 정보를 입력하거나 나중에 할 수 있어요."
      $btnStart.Visible = $false
      $btnNow.Visible   = $true
      $btnLater.Visible = $true
    } else {
      $status.Text      = "자동 설치를 완료하지 못했습니다. 위 안내를 확인하세요."
      $btnStart.Visible = $false
      $btnClose.Visible = $true
    }
  }
})

# ── 버튼 동작 ─────────────────────────────────────────────────────────────
$btnStart.Add_Click({
  $btnStart.Enabled = $false
  $log.Clear()
  $script:finalized = $false
  $sync.Progress = 0; $sync.Done = $false; $sync.Success = $false
  $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
  $ps = [powershell]::Create(); $ps.Runspace = $rs
  [void]$ps.AddScript($work).AddArgument($sync)
  $script:asyncPs = $ps
  [void]$ps.BeginInvoke()
  $timer.Start()
})

$btnNow.Add_Click({
  $bash  = Get-BashPath
  $setup = Get-SetupRel
  if ($bash -and $setup) {
    # 대화형 토큰/이름 입력은 콘솔(Git Bash)에서 이어받습니다.
    Start-Process -FilePath $bash -ArgumentList @($setup) -WorkingDirectory $scriptDir
  } else {
    [System.Windows.Forms.MessageBox]::Show("설치 파일(proj-sync-setup.sh)을 찾지 못했습니다. 같은 폴더에 두고 다시 실행하세요.", "안내") | Out-Null
  }
  $form.Close()
})

$btnLater.Add_Click({
  $bash    = Get-BashPath
  $plugDir = Get-PluginDir
  if ($bash -and $plugDir) {
    Start-Process -FilePath $bash -ArgumentList @("install.sh") -WorkingDirectory $plugDir
    [System.Windows.Forms.MessageBox]::Show("플러그인 설치 창을 열었습니다. 설치가 끝나면 그 창은 닫아도 됩니다.`r`n`r`n나중에 VS Code 터미널에서  bash proj-sync-setup.sh  로 토큰/이름을 입력하세요.`r`n(그 뒤 Claude Code 는 껐다 켜 주세요.)", "안내") | Out-Null
  } else {
    [System.Windows.Forms.MessageBox]::Show("플러그인 본체(proj-sync/install.sh)를 찾지 못했습니다. 압축을 올바르게 풀었는지 확인하세요.", "안내") | Out-Null
  }
  $form.Close()
})

$btnClose.Add_Click({ $form.Close() })

[void]$form.ShowDialog()
