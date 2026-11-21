$ErrorActionPreference = 'Stop'

# ARENA MRV - instalação segura a partir do downlad.zip
# Porta 8000 reservada para outro projeto; Arena MRV usa 8001 em diante.
$projeto = 'C:\Users\stefano.faria\Desktop\Nova pasta\DadosArenaMRV'
$zip = Join-Path $projeto 'downlad.zip'
$temp = $null
$logStdout = Join-Path $projeto 'arena_mrv_saida.log'
$logStderr = Join-Path $projeto 'arena_mrv_erro.log'

try {
    Write-Host "`n=== ARENA MRV | INSTALAR E INICIAR ===" -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) {
        throw "Arquivo downlad.zip não encontrado em: $zip"
    }

    $temp = Join-Path $env:TEMP ('ArenaMRV_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $temp -ItemType Directory -Force | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force

    # Localizar a raiz real do projeto, seja ela direta ou aninhada em um diretório.
    $candidatos = @(Get-ChildItem -LiteralPath $temp -Filter 'index.html' -File -Recurse | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.DirectoryName 'servidor.py') -PathType Leaf
    })
    if ($candidatos.Count -ne 1) {
        throw "Estrutura inválida no ZIP. Esperado exatamente um index.html acompanhado de servidor.py; encontrados: $($candidatos.Count)."
    }
    $origem = $candidatos[0].DirectoryName
    Write-Host "[1/5] ZIP validado. Origem: $origem" -ForegroundColor Green

    # Preservar os arquivos anteriores, sem tocar no ZIP nem em backups anteriores.
    $arquivos = @(Get-ChildItem -LiteralPath $origem -File -Recurse | Where-Object {
        $_.Name -ne 'downlad.zip'
    })
    $backup = Join-Path $projeto ('backups\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $copias = 0
    foreach ($arquivo in $arquivos) {
        $relativo = $arquivo.FullName.Substring($origem.Length).TrimStart('\', '/')
        $alvo = Join-Path $projeto $relativo
        if (Test-Path -LiteralPath $alvo -PathType Leaf) {
            $backupAlvo = Join-Path $backup $relativo
            New-Item -Path (Split-Path -Parent $backupAlvo) -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $alvo -Destination $backupAlvo -Force
            $copias++
        }
    }
    if ($copias -gt 0) { Write-Host "[2/5] Backup salvo: $backup" -ForegroundColor Green }
    else { Write-Host '[2/5] Nenhum arquivo anterior encontrado.' -ForegroundColor Cyan }

    foreach ($arquivo in $arquivos) {
        $relativo = $arquivo.FullName.Substring($origem.Length).TrimStart('\', '/')
        $alvo = Join-Path $projeto $relativo
        New-Item -Path (Split-Path -Parent $alvo) -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $arquivo.FullName -Destination $alvo -Force
    }
    $html = Join-Path $projeto 'index.html'
    $servidor = Join-Path $projeto 'servidor.py'
    if (-not (Test-Path -LiteralPath $html -PathType Leaf) -or -not (Test-Path -LiteralPath $servidor -PathType Leaf)) {
        throw "Falha na cópia. Veja se index.html e servidor.py existem em $projeto"
    }
    # Remover arquivos legados de alteracoes das versões anteriores, apenas da raiz do projeto.
    # Backups de projetos anteriores continuam preservados.
    Get-ChildItem -LiteralPath $projeto -File -Filter 'ALTERACOES_V*.txt' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^ALTERACOES_V[0-9]+\.txt$' } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host '[3/5] Arquivos instalados e verificados na pasta principal.' -ForegroundColor Green

    # Identificar Python instalado, evitando o alias da Microsoft Store.
    $pythonExe = $null
    $launchers = @()
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { $launchers += ,@($py.Source, '-3') }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) { $launchers += ,@($python.Source) }
    foreach ($launcher in $launchers) {
        try {
            if ($launcher.Count -gt 1) {
                $caminho = & $launcher[0] $launcher[1] -c 'import sys; print(sys.executable)' 2>$null
            } else {
                $caminho = & $launcher[0] -c 'import sys; print(sys.executable)' 2>$null
            }
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $caminho -PathType Leaf)) {
                $pythonExe = $caminho
                break
            }
        } catch {}
    }
    if (-not $pythonExe) { throw 'Python 3 não encontrado. Instale Python e tente novamente.' }

    # Reiniciar somente o Python deste projeto, se já estiver ativo.
    # Nunca tocar na porta 8000 nem em processos de outros projetos.
    $portasArena = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -ge 8001 -and $_.LocalPort -le 8020 })
    $idsArena = @($portasArena | Select-Object -ExpandProperty OwningProcess -Unique)
    foreach ($pidAlvo in $idsArena) {
        $info = Get-CimInstance Win32_Process -Filter "ProcessId=$pidAlvo" -ErrorAction SilentlyContinue
        if ($info -and $info.Name -match '^python.*\.exe$' -and $info.CommandLine -and
            $info.CommandLine.IndexOf($servidor, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Host "Reiniciando servidor anterior da Arena MRV (PID $pidAlvo)." -ForegroundColor Cyan
            Stop-Process -Id $pidAlvo -Force -ErrorAction Stop
        }
    }
    Start-Sleep -Milliseconds 300

    # Encontrar porta livre; não encerrar nenhum processo de outro projeto.
    $porta = $null
    foreach ($numero in 8001..8020) {
        if (-not (Get-NetTCPConnection -LocalPort $numero -State Listen -ErrorAction SilentlyContinue)) {
            $porta = $numero
            break
        }
    }
    if (-not $porta) { throw 'Nenhuma porta livre entre 8001 e 8020.' }
    Write-Host "[4/5] Python: $pythonExe | Porta: $porta | Porta 8000 preservada." -ForegroundColor Cyan

    # Salvar o erro do Python em arquivo para facilitar o diagnóstico.
    Remove-Item -LiteralPath $logStdout, $logStderr -ErrorAction SilentlyContinue
    $argumentos = '"{0}" --porta {1}' -f $servidor, $porta
    $processo = Start-Process -FilePath $pythonExe -ArgumentList $argumentos `
        -WorkingDirectory $projeto -PassThru `
        -RedirectStandardOutput $logStdout -RedirectStandardError $logStderr

    $url = "http://127.0.0.1:$porta/"
    $respondendo = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 350
        try {
            $resposta = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
            if ($resposta.StatusCode -eq 200 -and $resposta.Content -match 'Arena MRV') {
                $respondendo = $true
                break
            }
        } catch {}
        $processo.Refresh()
        if ($processo.HasExited) { break }
    }
    if (-not $respondendo) {
        $detalhes = ''
        if (Test-Path $logStderr) { $detalhes = (Get-Content $logStderr -Raw -ErrorAction SilentlyContinue) }
        if (-not $detalhes) { $detalhes = 'Sem erro no log; confira firewall e antivírus.' }
        throw "O servidor não respondeu em $url`nDetalhes do Python: $detalhes`nLog: $logStderr"
    }

    Write-Host '[5/5] Arena MRV iniciada com sucesso.' -ForegroundColor Green
    Write-Host "Site: http://localhost:$porta/"
    Write-Host "Admin: http://localhost:$porta/admin"
    Write-Host "Arquivos: $projeto"
    Start-Process "http://localhost:$porta/"
}
catch {
    Write-Host "`nERRO: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($temp -and (Test-Path -LiteralPath $temp)) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
