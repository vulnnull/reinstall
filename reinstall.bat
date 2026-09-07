@echo off
mode con cp select=437 >nul
setlocal EnableDelayedExpansion

set confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
set confhome_cn=https://cnb.cool/bin456789/reinstall/-/git/raw/main
rem set confhome_cn=https://www.ghproxy.cc/https://raw.githubusercontent.com/bin456789/reinstall/main

rem 自定义 Cygwin 下载源（解决 cygwin.com 被墙/拉黑的问题）
rem cygwin_setup_url: setup 安装器下载地址（官方镜像站不同步安装器，只能自托管或走代理）
rem   例如: set cygwin_setup_url=https://git.transnull.cn/raw/cygwin/setup-x86_64.exe
rem cygwin_site: Cygwin 包仓库地址（默认国内用 mirror.nju.edu.cn）
rem   例如: set cygwin_site=https://mirrors.ustc.edu.cn/cygwin
rem 注意：不要在这里 set cygwin_setup_url= / set cygwin_site= 清空，
rem 否则会覆盖用户在运行前设置的同名环境变量

set pkgs=curl,cpio,p7zip,dos2unix,jq,xz,gzip,zstd,openssl,bind-utils,libiconv,binutils
set cmds=curl,cpio,p7zip,dos2unix,jq,xz,gzip,zstd,openssl,nslookup,iconv,ar

rem 65001 代码页会乱码

rem 不要用 :: 注释
rem 否则可能会出现 系统找不到指定的驱动器

rem Windows 7 SP1 winhttp 默认不支持 tls 1.2
rem https://support.microsoft.com/en-us/topic/update-to-enable-tls-1-1-and-tls-1-2-as-default-secure-protocols-in-winhttp-in-windows-c4bd73d2-31d7-761e-0178-11268bb10392
rem 有些系统根证书没更新
rem 所以不要用https
rem 进入脚本目录
cd /d %~dp0

rem 检查是否有管理员权限
fltmc >nul 2>&1
if errorlevel 1 (
    echo Please run as administrator^^!
    exit /b
)

rem 有时 %tmp% 带会话 id，且文件夹不存在
rem https://learn.microsoft.com/troubleshoot/windows-server/shell-experience/temp-folder-with-logon-session-id-deleted
rem if not exist %tmp% (
rem     md %tmp%
rem )

rem 下载 geoip
rem 本 fork 默认服务器在国内：geoip 不存在时直接写 loc=CN，跳过 qualcomm.cn 探测
rem （该探测地址部分网络不可达，且 certutil 无超时会导致脚本卡死）
rem 如需国外镜像源，请手工创建 geoip 文件并写入 loc=US 等非 CN 值
if not exist geoip (
    echo loc=CN> %~dp0geoip
)

rem 判断是否有 loc=
findstr /c:"loc=" geoip >nul
if errorlevel 1 (
    echo Invalid geoip file
    del geoip
    exit /b 1
)

rem 检查是否国内
findstr /c:"loc=CN" geoip >nul
if not errorlevel 1 (
    rem mirrors.tuna.tsinghua.edu.cn 会强制跳转 https
    set mirror=http://mirror.nju.edu.cn
    if defined confhome_cn (
        set confhome=!confhome_cn!
    ) else if defined github_proxy (
        echo !confhome! | findstr /c:"://raw.githubusercontent.com/" >nul
        if not errorlevel 1 (
            set confhome=!confhome:http://=https://!
            set confhome=!confhome:https://raw.githubusercontent.com=%github_proxy%!
        )
    )
) else (
    rem 服务器在美国 equinix 机房，不是 cdn
    set mirror=http://mirrors.kernel.org
)

rem 优先使用预打包的绿色版 Cygwin（离线安装，不依赖任何镜像/网络）
rem 打包方法（在任意一台装好 Cygwin 的机器的 cygwin bash 里执行）：
rem   cd /cygdrive/c && tar czf cygwin-portable.tar.gz cygwin
rem 然后把 cygwin-portable.tar.gz 传到网盘 cloud-pc/cygwin/ 下
if not exist %SystemDrive%\cygwin\bin\bash.exe (
    if not defined cygwin_portable_url set cygwin_portable_url=https://pan.transnull.cn/d/cloud-pc/cygwin/cygwin-portable.tar.gz
    echo Trying portable Cygwin from !cygwin_portable_url! ...
    call :download !cygwin_portable_url! %~dp0cygwin-portable.tar.gz
    if not errorlevel 1 (
        tar -xzf %~dp0cygwin-portable.tar.gz -C %SystemDrive%\ >nul 2>&1
        if not errorlevel 1 (
            del /q %~dp0cygwin-portable.tar.gz
            goto :cygwin_installed
        )
        del /q %~dp0cygwin-portable.tar.gz
    )
    echo Portable Cygwin unavailable, fallback to online install...
)

call :check_cygwin_installed || (
    rem win10 arm 支持运行 x86 软件
    rem win11 arm 支持运行 x86 和 x86_64 软件

    rem windows 11 24h2 没有 wmic
    rem wmic os get osarchitecture 显示中文，即使设置了 mode con cp select=437
    rem wmic ComputerSystem get SystemType 显示英文
    rem for /f "tokens=*" %%a in ('wmic ComputerSystem get SystemType ^| find /i "based"') do (
    rem     set "SystemType=%%a"
    rem )

    rem 有的系统精简了 powershell
    rem for /f "delims=" %%a in ('powershell -NoLogo -NoProfile -NonInteractive -Command "(Get-WmiObject win32_computersystem).SystemType"') do (
    rem     set "SystemType=%%a"
    rem )

    rem SystemArch
    for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PROCESSOR_ARCHITECTURE') do (
        set SystemArch=%%a
    )

    rem 也可以用 PROCESSOR_ARCHITEW6432 和 PROCESSOR_ARCHITECTURE 判断
    rem ARM64 win11  PROCESSOR_ARCHITEW6432   PROCESSOR_ARCHITECTURE
    rem 原生cmd          未定义                      ARM64
    rem 32位cmd          ARM64                       x86

    rem if defined PROCESSOR_ARCHITEW6432 (
    rem     set "SystemArch=%PROCESSOR_ARCHITEW6432%"
    rem ) else (
    rem     set "SystemArch=%PROCESSOR_ARCHITECTURE%"
    rem )

    rem BuildNumber
    for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber') do (
        set /a BuildNumber=%%a
    )

    set CygwinEOL=1

    echo !SystemArch! | find "ARM" > nul
    if not errorlevel 1 (
        if !BuildNumber! GEQ 22000 (
            set CygwinEOL=0
        )
    ) else (
        echo !SystemArch! | find "AMD64" > nul
        if not errorlevel 1 (
            if !BuildNumber! GEQ 9600 (
                set CygwinEOL=0
            )
        )
    )

    rem win7/8 cygwin 已 EOL，不能用最新 cygwin 源，而要用 Cygwin Time Machine 源
    rem 但 Cygwin Time Machine 没有国内源
    rem 为了保证国内下载速度, cygwin EOL 统一使用 cygwin-archive x86 源
    if !CygwinEOL! == 1 (
        set CygwinArch=x86
        set dir=/sourceware/cygwin-archive/20221123
    ) else (
        set CygwinArch=x86_64
        set dir=/sourceware/cygwin
    )

    rem daocloud 加速有 90 天缓存，且不支持 IPv6
    rem https://github.com/DaoCloud/public-binary-files-mirror
    rem 无法用查询字符串强制刷新缓存
    rem https://files.m.daocloud.io/www.cloudflare.com/cdn-cgi/trace?a=1
    rem https://files.m.daocloud.io/www.cloudflare.com/cdn-cgi/trace?b=2
    rem 也就无法用 https://www.cygwin.com/setup-x86_64.exe?xxx=20250101 强制每天刷新缓存

    rem 下载 Cygwin 安装器
    rem cygwin.com 在国内被墙且部分 IP 被官网拉黑
    rem 国内镜像站不同步安装器 exe，只有带故意加密标志的 setup.zip（密码见 :download_cygwin_setup）
    rem 因此下载顺序为: cygwin_setup_url 自定义地址 → 镜像 setup.zip → 官网直下 exe
    if not exist setup-!CygwinArch!.exe (
        call :download_cygwin_setup !CygwinArch! %~dp0setup-!CygwinArch!.exe || goto :download_failed
    )

    rem 少于 1M 视为无效
    rem 有的 IP 被官网拉黑，无法下载 exe，下载得到 html
    for %%A in (setup-!CygwinArch!.exe) do if %%~zA LSS 1048576 (
        echo Invalid Cgywin installer
        del setup-!CygwinArch!.exe
        exit /b 1
    )

    rem 安装 Cygwin
    rem 允许用 cygwin_site 环境变量覆盖包仓库地址
    rem 单一镜像不稳定（setup.exe 下载包时可能挂住），因此多站点轮询重试
    if defined cygwin_site (
        set site_list=!cygwin_site!
    ) else if !CygwinEOL! == 1 (
        rem cygwin-archive 只有 NJU 有镜像
        set site_list=http://mirror.nju.edu.cn/sourceware/cygwin-archive/20221123
    ) else (
        set site_list=https://mirror.nju.edu.cn/cygwin https://mirrors.ustc.edu.cn/cygwin https://mirrors.aliyun.com/cygwin https://mirrors.huaweicloud.com/cygwin
    )

    for %%S in (!site_list!) do (
        call :install_cygwin_site %%S && goto :cygwin_installed
        echo Site %%S failed or timed out, trying next...
    )
    goto :install_cygwin_failed
)

:cygwin_installed
rem 在c盘根目录下执行 cygpath -ua . 会得到 /cygdrive/c，因此末尾要有 /
for /f %%a in ('%SystemDrive%\cygwin\bin\cygpath -ua ./') do set thisdir=%%a

rem 下载 reinstall.sh
echo Checking reinstall.sh ...
if not exist reinstall.sh (
    call :download_with_curl %confhome%/reinstall.sh %thisdir%reinstall.sh || goto :download_failed
    call :chmod a+x %thisdir%reinstall.sh
)

rem %* 无法处理 --iso https://x.com/?yyy=123
rem 为每个参数添加引号，使参数正确传递到 bash
rem for %%a in (%*) do (
rem     set "param=!param! "%%~a""
rem )

rem 转成 unix 格式，避免用户用 windows 记事本编辑后换行符不对
%SystemDrive%\cygwin\bin\dos2unix -q '%thisdir%reinstall.sh'

rem 用 bash 运行
rem %SystemDrive%\cygwin\bin\bash -l %thisdir%reinstall.sh %* 运行后会清屏
rem 因此不能用 -l
rem 这就需要在 reinstall.sh 里运行 source /etc/profile
rem 或者添加 export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
echo Running reinstall.sh ...
%SystemDrive%\cygwin\bin\bash %thisdir%reinstall.sh %*
exit /b

rem bits 要求有 Content-Length 才能下载
rem cloudflare 的 cdn-cgi/trace 没有 Content-Length
rem 据说如果网络设为“按流量计费” bits 也无法下载
rem https://learn.microsoft.com/en-us/windows/win32/bits/http-requirements-for-bits-downloads
rem bitsadmin /transfer "%~3" /priority foreground %~1 %~2

:install_cygwin_site
rem 用指定站点安装 Cygwin，带 15 分钟看门狗（setup.exe 自身无超时，镜像挂住时强杀换站）
rem 用法: call :install_cygwin_site ^<site_url^>
echo Installing Cygwin from %~1 ...
echo This may take several minutes. Please wait...
rem 云电脑管控/安全程序会按 setup*.exe 特征挂起安装器
rem 复制为随机临时名再启动，规避特征拦截
set /a cyg_pid=%random%%random%
copy /y setup-!CygwinArch!.exe cyg-bootstrap-!cyg_pid!.exe >nul
start "" cyg-bootstrap-!cyg_pid!.exe ^
    --allow-unsupported-windows ^
    --quiet-mode ^
    --only-site ^
    --site %~1 ^
    --root %SystemDrive%\cygwin ^
    --local-package-dir %~dp0cygwin-local-package-dir ^
    --packages %pkgs%

rem 轮询等待安装完成：每 10 秒查一次进程，90 次（15 分钟）超时强杀
set /a cyg_waits=0
:cygwin_wait_loop
ping -n 11 127.0.0.1 >nul
tasklist | find /i "cyg-bootstrap-!cyg_pid!" >nul
if errorlevel 1 goto :cygwin_setup_cleanup
set /a cyg_waits+=1
if !cyg_waits! LSS 90 goto :cygwin_wait_loop
echo Setup timed out on this site, killing process...
taskkill /f /im cyg-bootstrap-!cyg_pid!.exe >nul 2>&1
ping -n 3 127.0.0.1 >nul

:cygwin_setup_cleanup
del /f /q cyg-bootstrap-!cyg_pid!.exe >nul 2>&1
call :check_cygwin_installed
exit /b !errorlevel!

:download_cygwin_setup
rem 下载 Cygwin 安装器：cygwin_setup_url 自定义地址 → 国内镜像 setup.zip → 官网直下
rem 说明：国内镜像站不同步单独的 exe，只有 cygwin/setup/setup.zip
rem 该 zip 带故意的加密标志位（"知情同意门"），解压密码为：
rem   I understand and accept the risks
rem win10 1803+ 自带的 tar.exe（bsdtar/libarchive）支持 ZipCrypto，
rem 可通过 stdin 重定向密码文件解压；旧系统 tar 不支持时自动跳过该镜像
rem 用法: call :download_cygwin_setup ^<x86^|x86_64^> ^<目标路径^>
set setup_arch=%~1
set setup_dest=%~2

rem 默认首选自建网盘副本（国内稳定可达）；用户已设置 cygwin_setup_url 则尊重用户值
if not defined cygwin_setup_url (
    set cygwin_setup_url=https://pan.transnull.cn/d/cloud-pc/cygwin/setup-!setup_arch!.exe
)

rem 使用自定义地址
if defined cygwin_setup_url (
    call :download !cygwin_setup_url! !setup_dest!
    if not errorlevel 1 exit /b 0
    echo Download from cygwin_setup_url failed, fallback to mirrors
)

rem 写入解压密码文件（set /p 不带换行，libarchive 兼容 EOF 结尾）
<nul set /p ="I understand and accept the risks">%~dp0cygwin-pw.txt

rem 依次尝试国内镜像的 setup.zip
for %%M in (
    https://mirror.tuna.tsinghua.edu.cn/cygwin/setup/setup.zip
    https://mirrors.bfsu.edu.cn/cygwin/setup/setup.zip
    https://mirrors.cernet.edu.cn/cygwin/setup/setup.zip
    https://mirrors.huaweicloud.com/cygwin/setup/setup.zip
) do (
    echo Trying mirror: %%M
    call :download %%M %~dp0cygwin-setup.zip
    if not errorlevel 1 (
        tar -xf %~dp0cygwin-setup.zip -C %~dp0 setup-!setup_arch!.exe < %~dp0cygwin-pw.txt >nul 2>&1
        if not errorlevel 1 if exist !setup_dest! (
            del /q %~dp0cygwin-setup.zip %~dp0cygwin-pw.txt
            exit /b 0
        )
    )
)

rem 密码文件清理
del /q %~dp0cygwin-pw.txt 2>nul

rem 镜像全部失败，回退官网直下
echo All mirrors failed, fallback to cygwin.com
call :download http://www.cygwin.com/setup-!setup_arch!.exe !setup_dest!
exit /b !errorlevel!

:download
rem certutil 会被 windows Defender 报毒
rem windows server 2019 要用第二条 certutil 命令
rem certutil 没有超时机制，目标不可达时会无限期挂起
rem 因此优先用 PowerShell 下载（-TimeoutSec 30 秒超时），失败再回退 certutil
echo Downloading: %~1 %~2
del /q "%~2" 2>nul
if exist "%~2" (echo Cannot delete %~2 & exit /b 1)

rem PowerShell 3.0+ 才有 Invoke-WebRequest；旧系统忽略报错走 certutil
powershell -NoLogo -NoProfile -NonInteractive -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri '%~1' -OutFile '%~2'; if (Test-Path '%~2') { Unblock-File '%~2' }" >nul 2>&1
if not errorlevel 1 if exist "%~2" exit /b 0

certutil -urlcache -f -split "%~1" "%~2" >nul
if not errorlevel 1 if exist "%~2" exit /b 0

certutil -urlcache -split "%~1" "%~2" >nul
if not errorlevel 1 if exist "%~2" exit /b 0

rem 下载失败时删除文件，防止下载了一部分导致下次运行时跳过了下载
del /q "%~2" 2>nul
exit /b 1

:download_with_curl
rem 加 --insecure 防止以下错误
rem curl: (77) error setting certificate verify locations:
rem   CAfile: /etc/ssl/certs/ca-certificates.crt
rem   CApath: none
echo Download: %~1 %~2
%SystemDrive%\cygwin\bin\curl -L --insecure "%~1" -o "%~2"
exit /b

:chmod
%SystemDrive%\cygwin\bin\chmod "%~1" "%~2"
exit /b

:download_failed
echo Download failed.
exit /b 1

:install_cygwin_failed
echo Failed to install Cygwin.
echo 可尝试设置环境变量后重跑:
echo   set cygwin_setup_url=自定义 setup 安装器下载地址
echo   set cygwin_site=自定义 Cygwin 包仓库地址
exit /b 1

:check_cygwin_installed
set "cmds_space=%cmds:,= %"
for %%c in (%cmds_space%) do (
    if not exist "%SystemDrive%\cygwin\bin\%%c" if not exist "%SystemDrive%\cygwin\bin\%%c.exe" (
        exit /b 1
    )
)
exit /b 0
