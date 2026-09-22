# wpwpage
# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#
# Replaces the Windows desktop wallpaper with a web page, with full support
# for CSS and JavaScript (Chromium / WebView2): "WorkerW hack".
#
# Windows 10 (up-to-date) or Windows 11 where the WebView2 Runtime is present
# by default. You can download it: https://developer.microsoft.com/microsoft-edge/webview2.
#
# nim c -d:release --app:gui --threads:on wpwpage.nim
# wpwpage.exe <wpwpage.html>
# wpwpage.exe C:\chemin\page.html

#when not defined(windows):
#  {.error: "This program is specific to Windows.".}

import std/[json, os, strutils, threadpool]
import webview
#import winim/lean
#[
# webview.dll
# https://github.com/webview/webview/blob/master/webview.h
type WebviewHandle = pointer

const WebviewLib = if defined(windows): "webview.dll" else: "webview.dylib"
const WEBVIEW_HINT_FIXED: cint = 3

proc webview_create(debug: cint, window: pointer): WebviewHandle
  {.importc: "webview_create", dynlib: WebviewLib, cdecl.}
proc webview_destroy(w: WebviewHandle)
  {.importc: "webview_destroy", dynlib: WebviewLib, cdecl.}
proc webview_run(w: WebviewHandle)
  {.importc: "webview_run", dynlib: WebviewLib, cdecl.}
proc webview_terminate(w: WebviewHandle)
  {.importc: "webview_terminate", dynlib: WebviewLib, cdecl.}
proc webview_set_title(w: WebviewHandle, title: cstring)
  {.importc: "webview_set_title", dynlib: WebviewLib, cdecl.}
proc webview_set_size(w: WebviewHandle, width, height, hints: cint)
  {.importc: "webview_set_size", dynlib: WebviewLib, cdecl.}
proc webview_navigate(w: WebviewHandle, url: cstring)
  {.importc: "webview_navigate", dynlib: WebviewLib, cdecl.}
proc webview_get_window(w: WebviewHandle): pointer
  {.importc: "webview_get_window", dynlib: WebviewLib, cdecl.}
]#
#[
  # user32.dll
  # https://learn.microsoft.com/fr-fr/windows/win32/api/
  proc setWindowLongPtrA(hWnd: HWND, nIndex: int32, dwNewLong: int): int
    {.importc: "SetWindowLongPtrA", dynlib: "user32.dll", stdcall.}
  proc getWindowLongPtrA(hWnd: HWND, nIndex: int32): int
    {.importc: "GetWindowLongPtrA", dynlib: "user32.dll", stdcall.}
  proc setParent(hWndChild, hWndNewParent: HWND): HWND
    {.importc: "SetParent", dynlib: "user32.dll", stdcall.}
  proc moveWindow(hWnd: HWND, x, y, w, h: int32, bRepaint: int32): int32
    {.importc: "MoveWindow", dynlib: "user32.dll", stdcall.}
  proc showWindow(hWnd: HWND, nCmdShow: int32): int32
    {.importc: "ShowWindow", dynlib: "user32.dll", stdcall.}
  proc isWindow(hWnd: HWND): int32
    {.importc: "IsWindow", dynlib: "user32.dll", stdcall.}
  proc getSystemMetrics(nIndex: int32): int32
    {.importc: "GetSystemMetrics", dynlib: "user32.dll", stdcall.}

  # Searching for the WorkerW window (hidden).
  var gWorkerW: HWND = 0

  proc enumProc(hwnd: HWND, lParam: LPARAM): WINBOOL {.stdcall.} =
    var cls = newString(256)
    GetClassName(hwnd, cls, 256)

    # Look for the WorkerW that contains SHELLDLL_DefView.
    let defView = FindWindowEx(hwnd, 0, "SHELLDLL_DefView", nil)
    if defView != 0:
      gWorkerW = hwnd

    return TRUE

  proc findWorkerW(): HWND =
    let progman = FindWindow("Progman", nil)

    # Send 0x052C twice.
    SendMessageTimeout(progman, 0x052C, 0, 0, SMTO_NORMAL, 1000, nil)
    SendMessageTimeout(progman, 0x052C, 0, 0, SMTO_NORMAL, 1000, nil)
    # Test the windows.
    EnumWindows(enumProc, 0)
    return gWorkerW

  # Attaching the WebView window to WorkerW, full-screen, borderless.
  proc attachToDesktop(hwnd: HWND, workerW: HWND, screenW, screenH: int32) =
    var style = getWindowLongPtrA(hwnd, GWL_STYLE)
    style = style and not (WS_CAPTION or WS_THICKFRAME or WS_SYSMENU or
                            WS_MAXIMIZEBOX or WS_MINIMIZEBOX)
    discard setWindowLongPtrA(hwnd, GWL_STYLE, style)
    discard setParent(hwnd, workerW)
    discard moveWindow(hwnd, 0, 0, screenW, screenH, 1)
    discard showWindow(hwnd, SW_SHOW)

  # Monitors (in the background) and reattaches if necessary.
  proc watchdog(hwnd: HWND, screenW, screenH: int32) {.thread.} =
    while true:
      sleep(4000)
      if isWindow(hwnd) == 0: break
      let workerW = findWorkerW()
  #   if workerW != 0:
      if workerW != gWorkerW:
        attachToDesktop(hwnd, workerW, screenW, screenH)
]#

# Main program.
proc main() =
  let (path, name, _) = splitFile(paramStr(0))
  let htmlPath =
    if paramCount() >= 1:
      paramStr(1)
    else:
      path & "/" & name & ".htm"

  if not fileExists(htmlPath):
    quit "File not found: " & htmlPath

#  let workerW = findWorkerW()
#  if workerW == HWND(0):
#    quit "Unable to locate the WorkerW window: not supported by this version of Windows."

#  let screenW = getSystemMetrics(SM_CXSCREEN)
#  let screenH = getSystemMetrics(SM_CYSCREEN)
  let screenW = 800
  let screenH = 600

  let wv = newWebview(debug = true)
  defer: wv.destroy()
  wv.title = "wpwpage"
  wv.setSize(screenW.cint, screenH.cint, WebviewHintT.whFixed)
  wv.`bind`("runCmd") do (id: string, req: JsonNode) -> JsonNode:
    let cmd = req[0].getStr()
    let res = os.execShellCmd(cmd)
    %(res)

  let fileUrl = "file:///" & htmlPath.absolutePath.replace('\\', '/')
  wv.navigate(fileUrl)

  #let hwnd = cast[HWND](webview_get_window(wv))
  #attachToDesktop(hwnd, workerW, screenW, screenH)

  #spawn watchdog(hwnd, screenW, screenH)

  wv.run()

when isMainModule:
  main()
