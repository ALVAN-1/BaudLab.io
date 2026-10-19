; ============================================================
;  BaudLab - 自定义安装向导脚本（Linear 深色主题）
;  页面流程: 欢迎页 -> 安装方式选择页 -> (内置页跳过) ->
;            安装位置页 -> 安装进度页 -> 完成页
;  深色实现: MUI_BGCOLOR/MUI_TEXTCOLOR 官方配色 + SHOW 钩子
;  重着色原生目录/进度页; 勾选/单选因 NSIS bug #443 (文字色
;  不可改) 全部替换为静态文字行, 用显隐切换状态。
; ============================================================

; 将"目录页钩子"的影子 include 复制到 makensis 工作目录。
; cwd = node_modules\app-builder-lib\templates\nsis, NSIS !include
; 先搜 cwd 再搜 !addincludedir — 所以 build\StrContains.nsh 会先于
; 官方 include\StrContains.nsh 被 assistedInstaller.nsh 第23行命中,
; 在"安装方式页(19) 与 目录页(26) 之间"这个唯一窗口 emit SHOW define。
; 相对路径 4 层 .. 回到项目根; 复制失败仅告警并回落官方文件。
!system "cmd /c copy /y ..\..\..\..\build\StrContains.nsh StrContains.nsh"

; ---------------- 全局变量 ----------------
Var BL_Chosen        ; 安装方式选择: "all" / "user"
Var BL_FTitle        ; 标题字体 (Segoe UI 26 粗)
Var BL_FH2           ; 小标题字体 (Segoe UI 20 粗)
Var BL_FRadio        ; 行标题字体 (Segoe UI 16 半粗)
Var BL_FBody         ; 正文字体 (Segoe UI 14)
Var BL_FSmall        ; 辅助文字字体 (Segoe UI 13)
Var BL_Icon          ; 页面图标句柄
Var BL_Info          ; 选择页底部说明文字句柄
; 安装方式页第 1 行 (为所有用户): 面板/圆点/标题/说明 - 选中态 S / 未选中态 U
Var BL_P1S
Var BL_D1S
Var BL_T1S
Var BL_C1S
Var BL_P1U
Var BL_D1U
Var BL_T1U
Var BL_C1U
; 安装方式页第 2 行 (仅当前用户)
Var BL_P2S
Var BL_D2S
Var BL_T2S
Var BL_C2S
Var BL_P2U
Var BL_D2U
Var BL_T2U
Var BL_C2U
; 完成页 "立即启动" 行 (两套叠加)
Var BL_RunS
Var BL_RnDS
Var BL_RnTS
Var BL_RunU
Var BL_RnDU
Var BL_RnTU
Var BL_RunOn         ; 1 = 完成后启动应用 (默认)

; ---------------- Linear 深色调色板 (仅安装器编译) ----------------
; 卸载器保持浅色原生样式 (同一脚本两次编译, BUILD_UNINSTALLER 区分)
!ifndef BUILD_UNINSTALLER
  !define MUI_BGCOLOR 181920      ; 页头/页头图底色 (Interface.nsh 官方配色)
  !define MUI_TEXTCOLOR EEEFFC    ; 页头标题文字
!endif

; ============================================================
;  标题栏
; ============================================================
!macro customHeader
  !ifdef BUILD_UNINSTALLER
    Caption "${PRODUCT_NAME} 卸载程序"
  !else
    Caption "${PRODUCT_NAME} 安装程序"
  !endif
!macroend

; ============================================================
;  安装前关闭正在运行的实例（避免文件锁定导致安装失败）
;  同时创建页面所需的字体 + 深色标题栏
; ============================================================
!macro customInit
  DetailPrint "正在检查运行中的 ${PRODUCT_NAME}..."
  nsExec::Exec 'taskkill /F /IM "${APP_EXECUTABLE_FILENAME}"'
  Pop $0
  ${If} $0 == 0
    DetailPrint "已关闭旧进程，等待文件句柄释放..."
    Sleep 1500
  ${EndIf}

  ; 页面字体（中文由 GDI 字体链接回退到微软雅黑）
  CreateFont $BL_FTitle "Segoe UI" 26 700
  CreateFont $BL_FH2 "Segoe UI" 20 700
  CreateFont $BL_FRadio "Segoe UI" 16 600
  CreateFont $BL_FBody "Segoe UI" 14 400
  CreateFont $BL_FSmall "Segoe UI" 13 400

  !ifndef BUILD_UNINSTALLER
    ; 深色标题栏 (DWMWA_USE_IMMERSIVE_DARK_MODE: Win10 20H1+=20, 1809/1909=19)
    System::Call 'dwmapi::DwmSetWindowAttribute(p$HWNDPARENT, i20, *i 1, i4)'
    System::Call 'dwmapi::DwmSetWindowAttribute(p$HWNDPARENT, i19, *i 1, i4)'
  !endif
!macroend

; ============================================================
;  卸载前关闭运行中的实例
; ============================================================
!macro customUnInstall
  nsExec::Exec 'taskkill /F /IM "${APP_EXECUTABLE_FILENAME}"'
  Pop $0
  ${If} $0 == 0
    Sleep 1000
  ${EndIf}
!macroend

; ============================================================
;  额外快捷方式（开始菜单卸载项）
; ============================================================
!macro customInstall
  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\卸载.lnk" "$INSTDIR\${UNINSTALL_FILENAME}"
!macroend

; ============================================================
;  让内置"安装选项"页自动跳过:
;  由我们自己的选择页把结果写入 $BL_Chosen,
;  内置页 PRE 里的 customInstallMode 钩子读取后强制跳过它。
;  (卸载器 / --allusers / 提权实例中 $BL_Chosen 为空, 保持原有行为)
;  (目录页 SHOW define 已移到 build\StrContains.nsh 第23行处发:
;   本宏插入点之后, 同一次第19行展开里 multiUserUi.nsh:145 还有
;   一个 SHOW 消费点会把它吃掉, 且运行时 force-flag Abort 永远
;   到不了那里 — 编译被消费、运行永不执行, define 白发)
; ============================================================
!macro customInstallMode
  ${If} $BL_Chosen == "all"
    StrCpy $isForceMachineInstall "1"
  ${ElseIf} $BL_Chosen == "user"
    StrCpy $isForceCurrentInstall "1"
  ${EndIf}
!macroend

; ============================================================
;  目录页之后/进度页之前 — 在此重新定义 SHOW 钩子给
;  MUI_PAGE_INSTFILES 消费 (目录页展开时已把上一个 undef)
; ============================================================
!macro customPageAfterChangeDir
  !ifndef BUILD_UNINSTALLER
    !define MUI_PAGE_CUSTOMFUNCTION_SHOW BL_PageShow
  !endif
!macroend

; 本文件在生成脚本中的位置非常靠前 (addplugindir / MUI2 / UAC /
; WinMessages 都排在其后), 顶层直接写 Function 会导致这些依赖在
; 展开时还未就绪 — 因此全部包进 BL_PageFunctions 宏, 在
; customWelcomePage (模板区, 一切就绪) 处插入。
!macro BL_PageFunctions

!ifndef BUILD_UNINSTALLER

; ============================================================
;  向导框架条带深色化 (页头 + 品牌条 + 主窗口底色)
;  自定义页与原生页的 SHOW 钩子都会调用, 重复设置无副作用
; ============================================================
Function BL_DarkFrame
  SetCtlColors $HWNDPARENT "" 181920
  SetCtlColors $mui.Header.Background "" 181920
  SetCtlColors $mui.Branding.Background "" 181920
  SetCtlColors $mui.Branding.Text 8A8F98 181920
FunctionEnd

; ============================================================
;  原生页重着色 (目录页 / 进度页), 由 MUI2 SHOW 钩子调用
;  控件 ID 来自 MUI2 Directory.nsh / InstallFiles.nsh
; ============================================================
Function BL_PageShow
  Call BL_DarkFrame

  ; 当前页的子对话框 (nsDialogs 页面对话框, 类名 #32770)
  FindWindow $0 "#32770" "" $HWNDPARENT
  ${If} $0 != 0
    SetCtlColors $0 "" 181920

    ; 状态提示文字 (两页共用 ID 1006)
    GetDlgItem $1 $0 1006
    ${If} $1 != 0
      SetCtlColors $1 EEEFFC "transparent"
    ${EndIf}

    ; ---- 目录页: 1020 说明 1019 路径编辑框 1023/1024 空间统计 ----
    GetDlgItem $1 $0 1020
    ${If} $1 != 0
      SetCtlColors $1 8A8F98 "transparent"
    ${EndIf}
    GetDlgItem $1 $0 1019
    ${If} $1 != 0
      SetCtlColors $1 EEEFFC 12131A
    ${EndIf}
    GetDlgItem $1 $0 1023
    ${If} $1 != 0
      SetCtlColors $1 8A8F98 "transparent"
    ${EndIf}
    GetDlgItem $1 $0 1024
    ${If} $1 != 0
      SetCtlColors $1 8A8F98 "transparent"
    ${EndIf}

    ; ---- 进度页: 1004 进度条 1016 详细信息列表 ----
    GetDlgItem $1 $0 1004
    ${If} $1 != 0
      SendMessage $1 0x40A 0 0x00006BFF  ; PBM_SETBARCOLOR  橙 FF6B00 (BGR)
      SendMessage $1 0x409 0 0x00201918  ; PBM_SETBKCOLOR   深 181920 (BGR)
    ${EndIf}
    GetDlgItem $1 $0 1016
    ${If} $1 != 0
      SendMessage $1 0x1001 0 0x00201918 ; LVM_SETBKCOLOR
      SendMessage $1 0x1002 0 0x00201918 ; LVM_SETTEXTBKCOLOR
      SendMessage $1 0x1009 0 0x00FCFFEE ; LVM_SETTEXTCOLOR  EEEFFC (BGR)
    ${EndIf}
  ${EndIf}
FunctionEnd

; ============================================================
;  安装方式页: 行状态渲染 (显隐切换, 颜色随控件固定)
; ============================================================
Function BL_RowUpdate
  ${If} $BL_Chosen == "all"
    ShowWindow $BL_P1S ${SW_SHOW}
    ShowWindow $BL_D1S ${SW_SHOW}
    ShowWindow $BL_T1S ${SW_SHOW}
    ShowWindow $BL_C1S ${SW_SHOW}
    ShowWindow $BL_P1U ${SW_HIDE}
    ShowWindow $BL_D1U ${SW_HIDE}
    ShowWindow $BL_T1U ${SW_HIDE}
    ShowWindow $BL_C1U ${SW_HIDE}
    ShowWindow $BL_P2S ${SW_HIDE}
    ShowWindow $BL_D2S ${SW_HIDE}
    ShowWindow $BL_T2S ${SW_HIDE}
    ShowWindow $BL_C2S ${SW_HIDE}
    ShowWindow $BL_P2U ${SW_SHOW}
    ShowWindow $BL_D2U ${SW_SHOW}
    ShowWindow $BL_T2U ${SW_SHOW}
    ShowWindow $BL_C2U ${SW_SHOW}
    ${If} $hasPerMachineInstallation == "1"
      StrCpy $3 "已检测到现有安装，将升级：$\r$\n$perMachineInstallationFolder"
    ${Else}
      StrCpy $3 "全新安装 · 这台电脑的所有账户都可以使用"
    ${EndIf}
    ${If} ${UAC_IsAdmin}
      StrCpy $2 0
    ${Else}
      StrCpy $2 1 ; 非管理员选择"所有用户"时显示盾牌
    ${EndIf}
  ${Else}
    ShowWindow $BL_P1S ${SW_HIDE}
    ShowWindow $BL_D1S ${SW_HIDE}
    ShowWindow $BL_T1S ${SW_HIDE}
    ShowWindow $BL_C1S ${SW_HIDE}
    ShowWindow $BL_P1U ${SW_SHOW}
    ShowWindow $BL_D1U ${SW_SHOW}
    ShowWindow $BL_T1U ${SW_SHOW}
    ShowWindow $BL_C1U ${SW_SHOW}
    ShowWindow $BL_P2S ${SW_SHOW}
    ShowWindow $BL_D2S ${SW_SHOW}
    ShowWindow $BL_T2S ${SW_SHOW}
    ShowWindow $BL_C2S ${SW_SHOW}
    ShowWindow $BL_P2U ${SW_HIDE}
    ShowWindow $BL_D2U ${SW_HIDE}
    ShowWindow $BL_T2U ${SW_HIDE}
    ShowWindow $BL_C2U ${SW_HIDE}
    ${If} $hasPerUserInstallation == "1"
      StrCpy $3 "已检测到现有安装，将升级：$\r$\n$perUserInstallationFolder"
    ${Else}
      StrCpy $3 "全新安装 · 仅当前用户可用，无需管理员权限"
    ${EndIf}
    StrCpy $2 0
  ${EndIf}
  SendMessage $BL_Info ${WM_SETTEXT} 0 "STR:$3"
  ; 透明底静态文字换内容时的残影: 强制父对话框整区擦除重绘
  FindWindow $8 "#32770" "" $HWNDPARENT
  System::Call 'user32::RedrawWindow(p$8, p0, p0, i0x0185)' ; INVALIDATE|ERASE|ALLCHILDREN|UPDATENOW
  GetDlgItem $1 $HWNDPARENT 1 ; 下一步按钮
  SendMessage $1 ${BCM_SETSHIELD} 0 $2
FunctionEnd

Function BL_SelectAll
  StrCpy $BL_Chosen "all"
  Call BL_RowUpdate
FunctionEnd

Function BL_SelectUser
  StrCpy $BL_Chosen "user"
  Call BL_RowUpdate
FunctionEnd

; ============================================================
;  完成页 "立即启动" 行: 显隐切换
; ============================================================
Function BL_RunUpdate
  ${If} $BL_RunOn == "1"
    ShowWindow $BL_RunS ${SW_SHOW}
    ShowWindow $BL_RnDS ${SW_SHOW}
    ShowWindow $BL_RnTS ${SW_SHOW}
    ShowWindow $BL_RunU ${SW_HIDE}
    ShowWindow $BL_RnDU ${SW_HIDE}
    ShowWindow $BL_RnTU ${SW_HIDE}
  ${Else}
    ShowWindow $BL_RunS ${SW_HIDE}
    ShowWindow $BL_RnDS ${SW_HIDE}
    ShowWindow $BL_RnTS ${SW_HIDE}
    ShowWindow $BL_RunU ${SW_SHOW}
    ShowWindow $BL_RnDU ${SW_SHOW}
    ShowWindow $BL_RnTU ${SW_SHOW}
  ${EndIf}
FunctionEnd

Function BL_ToggleRun
  ${If} $BL_RunOn == "1"
    StrCpy $BL_RunOn "0"
  ${Else}
    StrCpy $BL_RunOn "1"
  ${EndIf}
  Call BL_RunUpdate
FunctionEnd

!endif ; BUILD_UNINSTALLER

!macroend ; BL_PageFunctions

; ============================================================
;  欢迎页 + 安装方式选择页（替代原生单选样式页）
; ============================================================
!macro customWelcomePage
  Page custom BL_WelcomeCreate
  Page custom BL_ModeCreate BL_ModeLeave

  ; 页面辅助函数 — 此位置 LogicLib/UAC/MUI2/插件均已就绪
  !insertmacro BL_PageFunctions

  ; ---------------- 欢迎页 ----------------
  Function BL_WelcomeCreate
    ${If} ${UAC_IsInnerInstance}
      Abort ; 提权重启后的实例直接进入"安装位置"页
    ${EndIf}

    !insertmacro MUI_HEADER_TEXT "欢迎安装 ${PRODUCT_NAME}" "安装前请确认以下信息"

    nsDialogs::Create 1018
    Pop $0
    SetCtlColors $0 "" 181920
    Call BL_DarkFrame

    ${NSD_CreateIcon} 14u 8u 28u 28u ""
    Pop $0
    ${NSD_SetIconFromInstaller} $0 $BL_Icon

    ${NSD_CreateLabel} 52u 8u 240u 26u "欢迎安装 ${PRODUCT_NAME}"
    Pop $0
    SendMessage $0 ${WM_SETFONT} $BL_FTitle 1
    SetCtlColors $0 EEEFFC "transparent"

    ${NSD_CreateLabel} 52u 38u 240u 14u "串口协议管理工具 · 版本 ${VERSION}"
    Pop $0
    SendMessage $0 ${WM_SETFONT} $BL_FSmall 1
    SetCtlColors $0 8A8F98 "transparent"

    ${NSD_CreateLabel} 14u 64u 272u 3u "" ; 橙色分隔条
    Pop $0
    SetCtlColors $0 FF6B00 FF6B00

    ; 功能要点 — 独立行, 行距 20u
    ${NSD_CreateLabel} 14u 78u 272u 13u "• 协议数据库：串口协议的管理与导入导出"
    Pop $0
    SendMessage $0 ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $0 C9CBD1 "transparent"

    ${NSD_CreateLabel} 14u 98u 272u 13u "• 实时报文编解码、抓包与标记"
    Pop $0
    SendMessage $0 ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $0 C9CBD1 "transparent"

    ${NSD_CreateLabel} 14u 118u 272u 13u "• AI 助手辅助分析与调试"
    Pop $0
    SendMessage $0 ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $0 C9CBD1 "transparent"

    nsDialogs::Show
  FunctionEnd

  ; ---------------- 安装方式选择页 ----------------
  ; 用可点击的静态文字行代替单选按钮 (NSIS bug #443:
  ; 主题控件文字色不可改, 深色底上黑字不可读)
  Function BL_ModeCreate
    ${If} ${UAC_IsInnerInstance}
      Abort ; 提权重启后的实例固定为"所有用户"，由内置页逻辑完成选择
    ${EndIf}
    ${If} ${isForAllUsers}
      Abort ; 命令行已指定 --allusers
    ${EndIf}
    ${If} ${isForCurrentUser}
      Abort ; 命令行已指定 --currentuser
    ${EndIf}

    !insertmacro MUI_HEADER_TEXT "安装选项" "选择将 ${PRODUCT_NAME} 安装给哪些用户"

    nsDialogs::Create 1018
    Pop $0
    SetCtlColors $0 "" 181920
    Call BL_DarkFrame

    ${NSD_CreateLabel} 14u 6u 272u 20u "选择安装方式"
    Pop $0
    SendMessage $0 ${WM_SETFONT} $BL_FH2 1
    SetCtlColors $0 EEEFFC "transparent"

    ; ---- 第 1 行: 为所有用户安装 (面板 + 选中/未选中两套文字叠加) ----
    ${NSD_CreateLabel} 14u 40u 272u 32u ""      ; 行面板 (卡片底)
    Pop $BL_P1S
    SetCtlColors $BL_P1S "" 1F2029

    ${NSD_CreateLabel} 22u 46u 12u 14u "●"      ; 选中态: 实心橙点
    Pop $BL_D1S
    SendMessage $BL_D1S ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $BL_D1S FF6B00 "transparent"

    ${NSD_CreateLabel} 38u 44u 244u 15u "为所有用户安装"
    Pop $BL_T1S
    SendMessage $BL_T1S ${WM_SETFONT} $BL_FRadio 1
    SetCtlColors $BL_T1S EEEFFC "transparent"

    ${NSD_CreateLabel} 38u 59u 244u 12u "安装到 Program Files，这台电脑的所有账户可用"
    Pop $BL_C1S
    SendMessage $BL_C1S ${WM_SETFONT} $BL_FSmall 1
    SetCtlColors $BL_C1S C9CBD1 "transparent"

    ${NSD_CreateLabel} 14u 40u 272u 32u ""      ; 同一行未选中态 (初始隐藏)
    Pop $BL_P1U
    SetCtlColors $BL_P1U "" 1F2029

    ${NSD_CreateLabel} 22u 46u 12u 14u "○"      ; 未选中态: 空心灰点
    Pop $BL_D1U
    SendMessage $BL_D1U ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $BL_D1U 55585F "transparent"

    ${NSD_CreateLabel} 38u 44u 244u 15u "为所有用户安装"
    Pop $BL_T1U
    SendMessage $BL_T1U ${WM_SETFONT} $BL_FRadio 1
    SetCtlColors $BL_T1U 8A8F98 "transparent"

    ${NSD_CreateLabel} 38u 59u 244u 12u "安装到 Program Files，这台电脑的所有账户可用"
    Pop $BL_C1U
    SendMessage $BL_C1U ${WM_SETFONT} $BL_FSmall 1
    SetCtlColors $BL_C1U 55585F "transparent"

    ; ---- 第 2 行: 仅为当前用户安装 ----
    System::Call "advapi32::GetUserName(t.r0,*i${NSIS_MAX_STRLEN})"

    ${NSD_CreateLabel} 14u 76u 272u 32u ""
    Pop $BL_P2S
    SetCtlColors $BL_P2S "" 1F2029

    ${NSD_CreateLabel} 22u 82u 12u 14u "●"
    Pop $BL_D2S
    SendMessage $BL_D2S ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $BL_D2S FF6B00 "transparent"

    ${NSD_CreateLabel} 38u 80u 244u 15u "仅为当前用户安装 ($0)"
    Pop $BL_T2S
    SendMessage $BL_T2S ${WM_SETFONT} $BL_FRadio 1
    SetCtlColors $BL_T2S EEEFFC "transparent"

    ${NSD_CreateLabel} 38u 95u 244u 12u "安装到个人应用目录，无需管理员权限"
    Pop $BL_C2S
    SendMessage $BL_C2S ${WM_SETFONT} $BL_FSmall 1
    SetCtlColors $BL_C2S C9CBD1 "transparent"

    ${NSD_CreateLabel} 14u 76u 272u 32u ""
    Pop $BL_P2U
    SetCtlColors $BL_P2U "" 1F2029

    ${NSD_CreateLabel} 22u 82u 12u 14u "○"
    Pop $BL_D2U
    SendMessage $BL_D2U ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $BL_D2U 55585F "transparent"

    ${NSD_CreateLabel} 38u 80u 244u 15u "仅为当前用户安装 ($0)"
    Pop $BL_T2U
    SendMessage $BL_T2U ${WM_SETFONT} $BL_FRadio 1
    SetCtlColors $BL_T2U 8A8F98 "transparent"

    ${NSD_CreateLabel} 38u 95u 244u 12u "安装到个人应用目录，无需管理员权限"
    Pop $BL_C2U
    SendMessage $BL_C2U ${WM_SETFONT} $BL_FSmall 1
    SetCtlColors $BL_C2U 55585F "transparent"

    ; 底部说明
    ${NSD_CreateLabel} 14u 114u 272u 28u ""
    Pop $BL_Info
    SendMessage $BL_Info ${WM_SETFONT} $BL_FSmall 1
    SetCtlColors $BL_Info EEEFFC "transparent"

    ; 行内任意位置点击 → 选择该行 (两套叠加控件都注册)
    ${NSD_OnClick} $BL_P1S BL_SelectAll
    ${NSD_OnClick} $BL_D1S BL_SelectAll
    ${NSD_OnClick} $BL_T1S BL_SelectAll
    ${NSD_OnClick} $BL_C1S BL_SelectAll
    ${NSD_OnClick} $BL_P1U BL_SelectAll
    ${NSD_OnClick} $BL_D1U BL_SelectAll
    ${NSD_OnClick} $BL_T1U BL_SelectAll
    ${NSD_OnClick} $BL_C1U BL_SelectAll
    ${NSD_OnClick} $BL_P2S BL_SelectUser
    ${NSD_OnClick} $BL_D2S BL_SelectUser
    ${NSD_OnClick} $BL_T2S BL_SelectUser
    ${NSD_OnClick} $BL_C2S BL_SelectUser
    ${NSD_OnClick} $BL_P2U BL_SelectUser
    ${NSD_OnClick} $BL_D2U BL_SelectUser
    ${NSD_OnClick} $BL_T2U BL_SelectUser
    ${NSD_OnClick} $BL_C2U BL_SelectUser

    ; 按 initMultiUser 的默认值预选 (已有安装时沿用原位置)
    ${If} $installMode == "all"
      StrCpy $BL_Chosen "all"
    ${Else}
      StrCpy $BL_Chosen "user"
    ${EndIf}
    Call BL_RowUpdate

    nsDialogs::Show
  FunctionEnd

  Function BL_ModeLeave
    ${If} $BL_Chosen == "all"
      ${IfNot} ${UAC_IsAdmin}
        ; 与原生页相同的提权流程: 用户取消时停留在本页而不是退出
        ShowWindow $HWNDPARENT ${SW_HIDE}
        !insertmacro UAC_RunElevated
        ${Switch} $0
          ${Case} 0
            ${If} $1 = 1
              Quit ; 外层进程退出, 提权实例继续完成安装
            ${EndIf}
            ${If} $1 = 3
            ${OrIf} $2 = 0x666666
              MessageBox mb_IconStop|mb_TopMost|mb_SetForeground "请使用具有管理员权限的账户登录后再试。"
            ${EndIf}
            ${Break}
          ${Case} 1223 ; 用户取消了 UAC
            ${Break}
          ${Case} 1062
            MessageBox mb_IconStop|mb_TopMost|mb_SetForeground "无法提权：Secondary Logon 服务未运行。"
            ${Break}
          ${Default}
            MessageBox mb_IconStop|mb_TopMost|mb_SetForeground "无法请求管理员权限，错误代码：$0"
            ${Break}
        ${EndSwitch}
        ShowWindow $HWNDPARENT ${SW_SHOW}
        BringToFront
        Abort ; 留在选择页
      ${EndIf}
    ${EndIf}
  FunctionEnd
!macroend

; ============================================================
;  完成页（替代原生完成页, 自带"立即启动"选项）
; ============================================================
!macro customFinishPage
  Page custom BL_FinishCreate BL_FinishLeave

  Function BL_FinishCreate
    !insertmacro MUI_HEADER_TEXT "完成安装" "${PRODUCT_NAME} 已成功安装"

    nsDialogs::Create 1018
    Pop $0
    SetCtlColors $0 "" 181920
    Call BL_DarkFrame

    ${NSD_CreateIcon} 14u 8u 28u 28u ""
    Pop $0
    ${NSD_SetIconFromInstaller} $0 $BL_Icon

    ${NSD_CreateLabel} 52u 8u 240u 26u "安装完成"
    Pop $0
    SendMessage $0 ${WM_SETFONT} $BL_FTitle 1
    SetCtlColors $0 EEEFFC "transparent"

    ${NSD_CreateLabel} 14u 48u 272u 30u "${PRODUCT_NAME} 已安装到：$\r$\n$INSTDIR"
    Pop $0
    SendMessage $0 ${WM_SETFONT} $BL_FSmall 1
    SetCtlColors $0 8A8F98 "transparent"

    ${NSD_CreateLabel} 14u 88u 272u 3u "" ; 橙色分隔条
    Pop $0
    SetCtlColors $0 FF6B00 FF6B00

    ; "立即启动" 行 — 点击切换, 两套叠加
    ${NSD_CreateLabel} 14u 100u 12u 14u "●"     ; 选中态
    Pop $BL_RunS
    SendMessage $BL_RunS ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $BL_RunS FF6B00 "transparent"

    ${NSD_CreateLabel} 28u 100u 240u 14u "立即启动 ${PRODUCT_NAME}"
    Pop $BL_RnTS
    SendMessage $BL_RnTS ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $BL_RnTS EEEFFC "transparent"

    ${NSD_CreateLabel} 14u 100u 12u 14u "○"     ; 未选中态
    Pop $BL_RunU
    SendMessage $BL_RunU ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $BL_RunU 55585F "transparent"

    ${NSD_CreateLabel} 28u 100u 240u 14u "立即启动 ${PRODUCT_NAME}"
    Pop $BL_RnTU
    SendMessage $BL_RnTU ${WM_SETFONT} $BL_FBody 1
    SetCtlColors $BL_RnTU 8A8F98 "transparent"

    ${NSD_CreateLabel} 14u 124u 280u 13u "可在 Windows 设置或控制面板中卸载"
    Pop $0
    SendMessage $0 ${WM_SETFONT} $BL_FSmall 1
    SetCtlColors $0 55585F "transparent"

    ${NSD_OnClick} $BL_RunS BL_ToggleRun
    ${NSD_OnClick} $BL_RnTS BL_ToggleRun
    ${NSD_OnClick} $BL_RunU BL_ToggleRun
    ${NSD_OnClick} $BL_RnTU BL_ToggleRun

    StrCpy $BL_RunOn "1"
    Call BL_RunUpdate

    nsDialogs::Show
  FunctionEnd

  Function BL_FinishLeave
    ${If} $BL_RunOn == "1"
      ${If} ${isUpdated}
        StrCpy $1 "--updated"
      ${Else}
        StrCpy $1 ""
      ${EndIf}
      ${StdUtils.ExecShellAsUser} $2 "$INSTDIR\${APP_EXECUTABLE_FILENAME}" "open" "$1"
    ${EndIf}
  FunctionEnd
!macroend
