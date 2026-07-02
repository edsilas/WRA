@echo off
rem ============================================================================
rem  Windows Resource Auditor
rem  Arquivo : Launcher.bat
rem  Versao  : 4.1.0
rem  Camada  : 0 - Bootstrap
rem  Autor   : Desenvolvido por Edsilas
rem  Funcao  : Inicializacao, validacao de ambiente, selecao do host PowerShell,
rem            verificacao de integridade, tratamento de privilegios/elevacao,
rem            logging de bootstrap e entrega de controle ao Core.ps1.
rem
rem  Regras  : Sem logica de dominio. Todas as strings emitidas sao ASCII puro
rem            (sem acentos) para compatibilidade com OEM codepages.
rem
rem  Codigos de saida (especificos do Launcher, faixa 10-19):
rem    10  Arquitetura nao x64 (AMD64 requerido)
rem    11  Nenhum host PowerShell compativel encontrado
rem    12  Host PowerShell abaixo da versao minima suportada
rem    13  Falha critica de integridade (Core.ps1 ausente)
rem  Em caso de handoff bem-sucedido, retorna o codigo de saida do Core.ps1
rem  (o Core reserva a faixa 30-99 para os seus proprios codigos).
rem ============================================================================

setlocal EnableExtensions EnableDelayedExpansion

rem ------------------------------------------------------------------ Constantes
set "WRA_PRODUCT=Windows Resource Auditor"
set "WRA_VERSION=4.1.0"
set "WRA_RC="

rem ------------------------------------------------- Resolucao da raiz do projeto
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

title %WRA_PRODUCT% v%WRA_VERSION%

rem ----------------------------------------------------- Parsing de argumentos
rem  Flags de controle do Launcher sao consumidas aqui e NAO repassadas ao Core.
rem  Demais argumentos sao acumulados (re-aspados) em CORE_ARGS.
set "CORE_ARGS="
set "SHOW_HELP="
set "WRA_ELEVATED="
set "WRA_NOELEVATE="
set "FORCE_PS5="
set "FORCE_PS7="

:parse
if "%~1"=="" goto parseEnd
set "A=%~1"
set "MATCHED="
if /i "!A!"=="--help" ( set "SHOW_HELP=1" & set "MATCHED=1" )
if /i "!A!"=="-h"     ( set "SHOW_HELP=1" & set "MATCHED=1" )
if /i "!A!"=="/?"     ( set "SHOW_HELP=1" & set "MATCHED=1" )
if /i "!A!"=="--elevated"  ( set "WRA_ELEVATED=1"  & set "MATCHED=1" )
if /i "!A!"=="--noelevate" ( set "WRA_NOELEVATE=1" & set "MATCHED=1" )
if /i "!A!"=="--ps5" ( set "FORCE_PS5=1" & set "MATCHED=1" )
if /i "!A!"=="--use-windows-powershell" ( set "FORCE_PS5=1" & set "MATCHED=1" )
if /i "!A!"=="--ps7" ( set "FORCE_PS7=1" & set "MATCHED=1" )
if /i "!A!"=="--use-pwsh" ( set "FORCE_PS7=1" & set "MATCHED=1" )
if not defined MATCHED set "CORE_ARGS=!CORE_ARGS! "%~1""
shift
goto parse
:parseEnd

if defined SHOW_HELP (
    call :Banner
    echo Uso: Launcher.bat [opcoes do launcher] [argumentos repassados ao Core]
    echo.
    echo Opcoes do launcher:
    echo   --ps7, --use-pwsh                Forca o uso do PowerShell 7 ou superior.
    echo   --ps5, --use-windows-powershell  Forca o uso do Windows PowerShell.
    echo   --noelevate                      Nao solicita elevacao; coleta parcial.
    echo   --help, -h, /?                   Exibe esta ajuda.
    echo.
    echo Demais argumentos sao repassados integralmente ao Core.ps1.
    set "WRA_RC=0"
    goto END
)

call :Banner

rem ------------------------------------------------------ Deteccao do host PS
call :DetectPwsh
call :DetectWinPS

set "PSHOST="
set "PSKIND="
set "PSMAJ="
set "HOST_PRESENT="

rem  Preferencia: Windows PowerShell 5.1 (runtime validado da ferramenta).
rem  pwsh 7+ e usado apenas como fallback (ou se forcado com --ps7).
if not defined FORCE_PS7 if defined WINPS (
    set "HOST_PRESENT=1"
    call :TryHost "%WINPS%" 4 "Windows PowerShell"
)
if not defined PSHOST if not defined FORCE_PS5 if defined PWSH (
    set "HOST_PRESENT=1"
    call :TryHost "%PWSH%" 7 "PowerShell"
)

rem ----------------------------------------------- Preparacao basica de logging
if not exist "%ROOT%\Logs\" mkdir "%ROOT%\Logs" >nul 2>&1
set "LOGFILE=%ROOT%\Logs\WRA_launcher.log"

if not defined PSHOST (
    if defined HOST_PRESENT (
        call :Log ERROR "Host PowerShell presente porem nao foi possivel confirmar a versao minima (PS 4.0 / PS 7+)."
        set "WRA_RC=12"
    ) else (
        call :Log ERROR "Nenhum host PowerShell encontrado (powershell.exe / pwsh.exe)."
        set "WRA_RC=11"
    )
    echo.
    echo [ERRO] PowerShell compativel nao disponivel. Diagnostico:
    if defined PWSH  ( echo   - pwsh detectado em:       "%PWSH%" ) else ( echo   - pwsh: nao encontrado no PATH )
    if defined WINPS ( echo   - powershell detectado em: "%WINPS%" ) else ( echo   - powershell: nao encontrado )
    echo   Tente executar manualmente para ver a versao:
    echo     powershell -NoProfile -Command $PSVersionTable.PSVersion
    goto END
)

rem ------------ Timestamp normalizado, data de log, versao do SO e do Config.json
set "WRA_CFG=%ROOT%\Config\Config.json"
call :PSEval NOW "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"
if defined NOW set "LOGDATE=!NOW:~0,4!!NOW:~5,2!!NOW:~8,2!"
if defined LOGDATE set "LOGFILE=%ROOT%\Logs\WRA_!LOGDATE!.log"

call :PSEval OSVER "[Environment]::OSVersion.VersionString"
call :PSEval CFG_VER "(Get-Content -Raw -LiteralPath $env:WRA_CFG | ConvertFrom-Json).Version"

call :Log INFO "===== Inicio de sessao do Launcher ====="
call :Log INFO "Produto: %WRA_PRODUCT% v%WRA_VERSION%"
call :Log INFO "Host:    %PSKIND%"
if defined OSVER call :Log INFO "SO:      %OSVER%"
call :Log INFO "Raiz:    %ROOT%"

rem ----------------------------------------------- Validacao de arquitetura x64
set "WRA_ARCH=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "WRA_ARCH=%PROCESSOR_ARCHITEW6432%"
if /i not "%WRA_ARCH%"=="AMD64" (
    call :Log ERROR "Arquitetura nao suportada: %WRA_ARCH%. Requerido x64 [AMD64]."
    echo.
    echo [ERRO] Esta ferramenta requer Windows x64. Detectado: %WRA_ARCH%.
    set "WRA_RC=10"
    goto END
)
call :Log INFO "Arquitetura: %WRA_ARCH% (OK)."

rem ----------------------------------------------------- Verificacao de integridade
set "INTEGRITY_WARN="

if not exist "%ROOT%\Core.ps1" (
    call :Log ERROR "Arquivo critico ausente: Core.ps1 (%ROOT%\Core.ps1)."
    echo.
    echo [ERRO] Core.ps1 nao encontrado. Estrutura do projeto incompleta.
    set "WRA_RC=13"
    goto END
)

call :CheckFile "%ROOT%\Config\Config.json"                       "Config.json"
call :CheckFile "%ROOT%\Config\Config.schema.json"                "Config.schema.json"
call :CheckFile "%ROOT%\Modules\Contracts\ResultEnvelope.psm1"    "Contracts\ResultEnvelope.psm1"
call :CheckFile "%ROOT%\Modules\Contracts\ModuleContract.psm1"    "Contracts\ModuleContract.psm1"
call :CheckDir  "%ROOT%\Modules\Infrastructure"                   "Modules\Infrastructure"
call :CheckDir  "%ROOT%\Modules\Domain"                           "Modules\Domain"

if defined INTEGRITY_WARN (
    call :Log WARN "Integridade parcial: itens ausentes detectados. O Core validara em detalhe."
) else (
    call :Log INFO "Integridade da estrutura: OK."
)

rem ------------------------------------------- Verificacao de versao (offline)
if defined CFG_VER (
    if /i not "%CFG_VER%"=="%WRA_VERSION%" (
        call :Log WARN "Versao do Config.json (%CFG_VER%) difere da esperada (%WRA_VERSION%)."
    ) else (
        call :Log INFO "Versao do Config.json: %CFG_VER% (OK)."
    )
) else (
    call :Log WARN "Nao foi possivel ler a versao em Config.json."
)

rem ----------------------------------------- Validacao de privilegios e elevacao
call :CheckAdmin
if defined IS_ADMIN (
    call :Log INFO "Privilegios: elevado (Administrador)."
) else (
    if defined WRA_NOELEVATE (
        call :Log WARN "Sem elevacao (--noelevate). A coleta de dados privilegiados sera parcial."
    ) else if defined WRA_ELEVATED (
        call :Log WARN "Elevacao nao obtida apos tentativa. Prosseguindo com coleta parcial."
    ) else (
        call :Log INFO "Solicitando elevacao de privilegios via UAC..."
        set "WRA_SELF=%~f0"
        set "WRA_FWD=%* --elevated"
        "%PSHOST%" -NoProfile -ExecutionPolicy Bypass -Command "try{Start-Process -FilePath $env:WRA_SELF -ArgumentList $env:WRA_FWD -Verb RunAs -ErrorAction Stop; exit 0}catch{exit 5}"
        if errorlevel 1 (
            call :Log WARN "Elevacao recusada ou indisponivel. Prosseguindo com coleta parcial."
        ) else (
            call :Log INFO "Instancia elevada iniciada. Encerrando instancia nao elevada."
            set "SILENT_EXIT=1"
            set "WRA_RC=0"
            goto END
        )
    )
)

rem ---------------------------------------------- Rotulo de privilegios p/ menu
if defined IS_ADMIN (
    set "PRIVLABEL=Elevado (Administrador)"
) else (
    set "PRIVLABEL=Parcial (sem elevacao)"
)

rem -------------------------------------------------------- Entrega ao Core.ps1
rem  Com argumentos explicitos -> execucao direta (uso em scripts/agendador).
rem  Sem argumentos            -> menu interativo.
if defined CORE_ARGS goto DirectRun
goto Menu


rem ============================================================================
rem  SUB-ROTINAS
rem ============================================================================

:Banner
echo.
echo  ==========================================================
echo   %WRA_PRODUCT%  v%WRA_VERSION%
echo   Auditoria, monitoramento e inventario para Windows
echo  ==========================================================
echo.
goto :eof

:DetectPwsh
rem Localiza o PowerShell 7+ (pwsh.exe) no PATH, se existir.
set "PWSH="
for /f "usebackq delims=" %%p in (`where pwsh 2^>nul`) do if not defined PWSH set "PWSH=%%p"
goto :eof

:DetectWinPS
rem Resolve o Windows PowerShell nativo de 64 bits. Em contexto de 32 bits
rem (PROCESSOR_ARCHITEW6432 definido) usa o caminho virtual Sysnative para
rem alcancar o host de 64 bits, evitando a versao de 32 bits sob SysWOW64.
set "WINPS="
if defined PROCESSOR_ARCHITEW6432 (
    set "WINPS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
) else (
    set "WINPS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
)
if not exist "%WINPS%" set "WINPS="
if not defined WINPS for /f "usebackq delims=" %%p in (`where powershell 2^>nul`) do if not defined WINPS set "WINPS=%%p"
goto :eof

:TryHost
rem %1=executavel  %2=major minimo  %3=rotulo. Define PSHOST/PSKIND/PSMAJ se apto.
if defined PSHOST goto :eof
set "_EXE=%~1"
set "_MIN=%~2"
set "_LBL=%~3"
set "PSMAJOR="
rem  Probe primario: captura direta (sem aspas internas; a expressao nao tem espacos).
for /f "usebackq delims=" %%m in (`"%_EXE%" -NoProfile -NoLogo -ExecutionPolicy Bypass -Command $PSVersionTable.PSVersion.Major 2^>nul`) do set "PSMAJOR=%%m"
rem  Probe secundario (fallback): arquivo temporario em ASCII, evita aspas e BOM.
if not defined PSMAJOR (
    set "_TMP=%TEMP%\wra_ver_%RANDOM%%RANDOM%.txt"
    "%_EXE%" -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "[System.IO.File]::WriteAllText('!_TMP!',[string]$PSVersionTable.PSVersion.Major)" >nul 2>&1
    if exist "!_TMP!" (
        set /p PSMAJOR=<"!_TMP!"
        del "!_TMP!" >nul 2>&1
    )
)
if not defined PSMAJOR goto :eof
set "PSMAJOR=%PSMAJOR: =%"
set /a "_N=%PSMAJOR%" >nul 2>&1
if not "%_N%"=="%PSMAJOR%" goto :eof
if %PSMAJOR% LSS %_MIN% goto :eof
set "PSHOST=%_EXE%"
set "PSMAJ=%PSMAJOR%"
set "PSKIND=%_LBL% %PSMAJOR%.x"
goto :eof

:CheckFile
if not exist "%~1" (
    set "INTEGRITY_WARN=1"
    call :Log WARN "Ausente: %~2"
)
goto :eof

:CheckDir
if not exist "%~1\" (
    set "INTEGRITY_WARN=1"
    call :Log WARN "Ausente (diretorio): %~2"
)
goto :eof

:CheckAdmin
rem Probe de privilegios. fltmc requer elevacao e independe do servidor "Server".
rem net session e usado como confirmacao secundaria.
set "IS_ADMIN="
fltmc >nul 2>&1
if not errorlevel 1 (
    set "IS_ADMIN=1"
    goto :eof
)
net session >nul 2>&1
if not errorlevel 1 set "IS_ADMIN=1"
goto :eof

:PSEval
rem  %1=variavel de saida  %2=expressao PowerShell. Executa via arquivo temporario
rem  ASCII (execucao direta, sem for /f), evitando problemas de aspas/parenteses.
set "_EVAL_VAR=%~1"
set "%_EVAL_VAR%="
set "_EVAL_TMP=%TEMP%\wra_eval_%RANDOM%%RANDOM%.txt"
"%PSHOST%" -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "try{[System.IO.File]::WriteAllText('%_EVAL_TMP%',[string](%~2))}catch{}" >nul 2>&1
if exist "%_EVAL_TMP%" (
    for /f "usebackq delims=" %%x in ("%_EVAL_TMP%") do set "%_EVAL_VAR%=%%x"
    del "%_EVAL_TMP%" >nul 2>&1
)
goto :eof

:Log
rem %1=nivel  %2=mensagem. Troca ( ) por [ ] na mensagem para nunca acionar o
rem parser de blocos do cmd (causa de ". was unexpected at this time.").
set "_LVL=%~1"
set "_MSG=%~2"
if defined _MSG set "_MSG=!_MSG:(=[!"
if defined _MSG set "_MSG=!_MSG:)=]!"
if defined NOW (set "_TS=%NOW%") else (set "_TS=%DATE% %TIME%")
if defined LOGFILE (
    >>"%LOGFILE%" echo !_TS! [!_LVL!] [LAUNCHER] !_MSG!
)
echo   [!_LVL!] !_MSG!
goto :eof


:DirectRun
rem  Execucao nao-interativa: repassa CORE_ARGS exatamente como recebidos.
call :Log INFO "Iniciando Core.ps1 (%PSKIND%)..."
echo.
"%PSHOST%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\Core.ps1"%CORE_ARGS%
set "WRA_RC=!errorlevel!"
echo.
call :Log INFO "Core.ps1 finalizado com codigo de saida !WRA_RC!."
goto END


:Menu
cls
call :Banner
echo   Host: %PSKIND%      Privilegios: %PRIVLABEL%
echo  ----------------------------------------------------------
echo.
echo     [1]  Auditoria completa (todos os modulos)
echo     [2]  Inventario      (hardware, SO, software)
echo     [3]  Monitoramento   (servicos, processos, eventos)
echo     [4]  Rede            (interfaces, conexoes, portas, shares)
echo     [5]  Processos       (analise detalhada e assinaturas)
echo     [6]  Seguranca       (firewall, BitLocker, contas, updates)
echo.
echo     [7]  Listar modulos disponiveis
echo     [8]  Abrir ultimo relatorio (dashboard HTML)
echo     [9]  Agendar execucao automatica (tarefa diaria)
echo.
echo     [0]  Sair
echo.
echo  ----------------------------------------------------------
echo                                    Desenvolvido por Edsilas
echo.
set "OPT="
set /p "OPT=  Escolha uma opcao e tecle ENTER: "
if not defined OPT goto Menu
set "OPT=!OPT: =!"

echo(!OPT!| findstr /r "^[0-9]$" >nul
if errorlevel 1 (
    echo.
    echo   Opcao invalida: "!OPT!". Use um numero de 0 a 9.
    goto MenuPause
)

if "!OPT!"=="0" goto MenuExit
if "!OPT!"=="1" call :RunCore -Run All
if "!OPT!"=="2" call :RunCore -Run Inventory
if "!OPT!"=="3" call :RunCore -Run Monitor
if "!OPT!"=="4" call :RunCore -Run Network
if "!OPT!"=="5" call :RunCore -Run ProcessAnalyzer
if "!OPT!"=="6" call :RunCore -Run Security
if "!OPT!"=="7" call :RunCore -ListModules
if "!OPT!"=="8" call :OpenDashboard
if "!OPT!"=="9" call :RunCore -InstallSchedule
goto MenuPause

:MenuPause
echo.
echo   Pressione qualquer tecla para voltar ao menu...
pause >nul
goto Menu

:MenuExit
call :Log INFO "Menu encerrado pelo usuario."
set "SILENT_EXIT=1"
set "WRA_RC=0"
goto END

:OpenDashboard
set "DASH=%ROOT%\Reports\Latest\dashboard.html"
if exist "!DASH!" (
    call :Log INFO "Abrindo dashboard: !DASH!"
    start "" "!DASH!"
    echo.
    echo   Dashboard aberto no navegador padrao.
) else (
    echo.
    echo   Nenhum relatorio encontrado ainda.
    echo   Rode uma auditoria primeiro - opcao 1 a 6.
)
goto :eof

:RunCore
rem  Executa o Core.ps1 com os argumentos recebidos (%*) e registra o resultado.
rem  A barra de progresso e exibida pelo proprio Core (Write-Progress nativo).
call :Log INFO "Executando: Core.ps1 %*"
echo.
"%PSHOST%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\Core.ps1" %*
set "CORE_EXIT=!errorlevel!"
echo.
if "!CORE_EXIT!"=="0" (
    call :Log INFO "Concluido com sucesso (codigo !CORE_EXIT!)."
) else (
    call :Log WARN "Core.ps1 retornou codigo !CORE_EXIT!. Verifique os logs em Logs\."
)
goto :eof


:END
if not defined WRA_RC set "WRA_RC=0"
if defined LOGFILE (
    if defined NOW (set "_TS=%NOW%") else (set "_TS=%DATE% %TIME%")
    >>"%LOGFILE%" echo !_TS! [INFO] [LAUNCHER] Launcher encerrado - codigo !WRA_RC!.
)
rem  Em modo interativo (sem argumentos), nao deixa a janela fechar sem o usuario
rem  ver a ultima mensagem. O "Sair" do menu e a re-elevacao definem SILENT_EXIT.
if not defined CORE_ARGS if not defined SILENT_EXIT (
    echo.
    echo   [Launcher encerrado - codigo !WRA_RC!]
    echo   Pressione qualquer tecla para fechar esta janela...
    pause >nul
)
endlocal & exit /b %WRA_RC%
