; ============================================================
;  BaudLab Linear 主题 — StrContains.nsh 影子文件 (编译顺序利用)
;
;  机制: electron-builder 让 makensis 以 node_modules\app-builder-lib\
;  templates\nsis 为工作目录, 而 NSIS !include 搜索顺序实测为
;  "当前目录 > !addincludedir(先加先搜) > NSIS自带Include" —
;  因此本文件会先于官方 include\StrContains.nsh 被
;  assistedInstaller.nsh 第23行 (!include StrContains.nsh) 命中。
;
;  为什么必须在第23行: 第19行 PAGE_INSTALL_MODE 展开体内,
;  multiUserUi.nsh 第145行 (安装方式页函数内) 有一个
;  MUI_PAGE_FUNCTION_CUSTOM SHOW 消费点, 会吃掉更早发出的
;  MUI_PAGE_CUSTOMFUNCTION_SHOW define — 且该处运行时因
;  force-flag Abort 永远执行不到。第23行位于第19行之后、
;  第26行 MUI_PAGE_DIRECTORY 之前, 是唯一能存活到
;  Directory.nsh:119 (目录页 SHOW 消费点) 的发射窗口。
;
;  更新维护: 本文件由 build\installer.nsh 顶部的 !system copy
;  在每次构建时复制到 makensis 工作目录 (自愈, npm 重装后仍生效)。
;  复制失败时 NSIS 仅告警, 回落官方文件 (症状: 目录页不深色)。
;  下方正文为官方 include\StrContains.nsh 原文, 升级
;  electron-builder 时请 diff 同步。
; ============================================================
!ifndef BUILD_UNINSTALLER
  !define MUI_PAGE_CUSTOMFUNCTION_SHOW BL_PageShow
!endif

; ==== 以下为官方 templates\nsis\include\StrContains.nsh 原文 ====
; StrContains
; This function does a case sensitive searches for an occurrence of a substring in a string.
; It returns the substring if it is found.
; Otherwise it returns null("").
; Written by kenglish_hi
; Adapted from StrReplace written by dandaman32


Var STR_HAYSTACK
Var STR_NEEDLE
Var STR_CONTAINS_VAR_1
Var STR_CONTAINS_VAR_2
Var STR_CONTAINS_VAR_3
Var STR_CONTAINS_VAR_4
Var STR_RETURN_VAR

Function StrContains
  Exch $STR_NEEDLE
  Exch 1
  Exch $STR_HAYSTACK
  ; Uncomment to debug
  ;MessageBox MB_OK 'STR_NEEDLE = $STR_NEEDLE STR_HAYSTACK = $STR_HAYSTACK '
    StrCpy $STR_RETURN_VAR ""
    StrCpy $STR_CONTAINS_VAR_1 -1
    StrLen $STR_CONTAINS_VAR_2 $STR_NEEDLE
    StrLen $STR_CONTAINS_VAR_4 $STR_HAYSTACK
    loop:
      IntOp $STR_CONTAINS_VAR_1 $STR_CONTAINS_VAR_1 + 1
      StrCpy $STR_CONTAINS_VAR_3 $STR_HAYSTACK $STR_CONTAINS_VAR_2 $STR_CONTAINS_VAR_1
      StrCmp $STR_CONTAINS_VAR_3 $STR_NEEDLE found
      StrCmp $STR_CONTAINS_VAR_1 $STR_CONTAINS_VAR_4 done
      Goto loop
    found:
      StrCpy $STR_RETURN_VAR $STR_NEEDLE
      Goto done
    done:
   Pop $STR_NEEDLE ;Prevent "invalid opcode" errors and keep the
   Exch $STR_RETURN_VAR
FunctionEnd

!macro _StrContainsConstructor OUT NEEDLE HAYSTACK
  Push `${HAYSTACK}`
  Push `${NEEDLE}`
  Call StrContains
  Pop `${OUT}`
!macroend

!define StrContains '!insertmacro "_StrContainsConstructor"'
