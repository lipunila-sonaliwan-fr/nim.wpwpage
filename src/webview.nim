## High-level, idiomatic Nim API for https://github.com/webview/webview,
## built entirely on top of the raw C API bindings in `webviewcapi.nim`.
## No other webview wrapper or browser/GUI component is used.
##
## The two-way JavaScript bridge is exposed as:
## * `eval()`     - Nim -> JavaScript: evaluate arbitrary JS code.
## * `dispatch()` - Nim -> JavaScript: schedule a Nim closure to run on the
##                  UI thread (required to call `eval` safely once the
##                  event loop is running, and to call *any* webview
##                  function safely from a background thread).
## * `bind()`     - JavaScript -> Nim: expose a Nim closure as a global
##                  async JavaScript function. Arguments and the result
##                  are automatically encoded/decoded as JSON.

import std/[json, tables]
import webviewcapi

export WebviewErrorT, WebviewHintT, WebviewNativeHandleKindT

type
  Webview* = ref object
    ## Idiomatic handle wrapping the raw `WebviewT` C pointer.
    handle*: WebviewT

  WebviewError* = object of CatchableError
    ## Raised whenever a `webview_*` call reports an error code.

  BindHandler* = proc (id: string; req: JsonNode): JsonNode {.closure.}
    ## Handler for a JavaScript -> Nim binding. `req` is the JSON array of
    ## arguments passed from JavaScript; the returned `JsonNode` becomes
    ## the value the JS-side Promise resolves to.

  DispatchHandler* = proc (w: Webview) {.closure.}
    ## Handler scheduled to run on the UI thread by `dispatch`.

  BindEntry = object
    ## Named record type (deliberately NOT an anonymous tuple: a tuple
    ## mixing a `ref object` field and a closure field, stored inside a
    ## generic `Table`, has been observed to crash Nim's C++ backend -
    ## `Error: internal error: getTypeDescAux(tyNone)` - a named `object`
    ## avoids the issue).
    w: Webview
    fn: BindHandler

# ---------------------------------------------------------------------
# Internal callback registries
# ---------------------------------------------------------------------
# `webview_bind` and `webview_dispatch` only accept a plain C function
# pointer plus a `void*` user argument - the C API has no notion of a Nim
# closure environment. To still expose real Nim closures (able to capture
# outer variables such as `w`) in the high-level API, every registered
# closure is kept alive in a global table, and only its integer id
# travels through the `void*` argument. A single small `{.cdecl.}`
# trampoline per callback kind looks the closure back up by id and calls
# it; because it takes no captured Nim state itself, it needs no closure
# environment and can be passed to the C API as-is.

var bindHandlers = initTable[int, BindEntry]()
var dispatchHandlers = initTable[int, DispatchHandler]()
var nextHandlerId = 0

proc checkError(err: WebviewErrorT; what: string) =
  if err != weOk:
    raise newException(WebviewError, what & " failed with error code " & $ord(err))

proc bindTrampoline(id, req: cstring; arg: pointer) {.cdecl.} =
  let handlerId = cast[int](arg)
  let entry = bindHandlers[handlerId]
  var status: cint = 0
  var resultJson: JsonNode
  try:
    resultJson = entry.fn($id, parseJson($req))
  except CatchableError as e:
    status = 1
    resultJson = %*{"error": e.msg}
  discard webview_return(entry.w.handle, id, status, ($resultJson).cstring)

proc dispatchTrampoline(w: WebviewT; arg: pointer) {.cdecl.} =
  let handlerId = cast[int](arg)
  let fn = dispatchHandlers[handlerId]
  dispatchHandlers.del(handlerId)
  fn(Webview(handle: w))

# ---------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------

proc newWebview*(debug = false): Webview =
  ## Creates a new, top-level webview window.
  let handle = webview_create(if debug: 1.cint else: 0.cint, nil)
  if handle.isNil:
    raise newException(WebviewError,
      "webview_create failed (is the native webview runtime installed?)")
  result = Webview(handle: handle)

proc destroy*(w: Webview) =
  ## Destroys the webview and closes its native window.
  checkError webview_destroy(w.handle), "webview_destroy"

proc run*(w: Webview) =
  ## Runs the native event loop until the window is closed or
  ## `terminate` is called.
  checkError webview_run(w.handle), "webview_run"

proc terminate*(w: Webview) =
  ## Stops the event loop started by `run`. Safe to call from another
  ## thread.
  checkError webview_terminate(w.handle), "webview_terminate"

# ---------------------------------------------------------------------
# Window / content configuration
# ---------------------------------------------------------------------

proc `title=`*(w: Webview; title: string) =
  ## Sets the native window title.
  checkError webview_set_title(w.handle, title.cstring), "webview_set_title"

proc setSize*(w: Webview; width, height: int; hints = whNone) =
  ## Sets the native window size, optionally with min/max/fixed hints.
  checkError webview_set_size(w.handle, width.cint, height.cint, hints.ord.cint),
             "webview_set_size"

proc `size=`*(w: Webview; size: tuple[width, height: int]) =
  ## Setter alias for `setSize` with `WebviewHintT.whNone`.
  w.setSize(size.width, size.height)

proc navigate*(w: Webview; url: string) =
  ## Navigates to `url`, which may be a regular URL or a data: URI.
  checkError webview_navigate(w.handle, url.cstring), "webview_navigate"

proc `html=`*(w: Webview; html: string) =
  ## Loads `html` directly as the page content.
  checkError webview_set_html(w.handle, html.cstring), "webview_set_html"

proc injectOnLoad*(w: Webview; js: string) =
  ## Injects JavaScript that runs before every page load, ahead of any
  ## other script on the page (wraps `webview_init`).
  checkError webview_init(w.handle, js.cstring), "webview_init"

# ---------------------------------------------------------------------
# Nim -> JavaScript
# ---------------------------------------------------------------------

proc eval*(w: Webview; js: string) =
  ## Evaluates arbitrary JavaScript inside the page. Only safe to call
  ## once the event loop is running - e.g. from inside a `dispatch` or
  ## `bind` callback.
  checkError webview_eval(w.handle, js.cstring), "webview_eval"

proc dispatch*(w: Webview; fn: DispatchHandler) =
  ## Schedules `fn` to run on the UI thread as soon as the event loop
  ## allows it. Use this to call `eval` (or any other webview operation)
  ## right after `run()` starts, or safely from a background thread.
  let id = nextHandlerId
  inc nextHandlerId
  dispatchHandlers[id] = fn
  checkError webview_dispatch(w.handle, dispatchTrampoline, cast[pointer](id)),
             "webview_dispatch"

# ---------------------------------------------------------------------
# JavaScript -> Nim
# ---------------------------------------------------------------------

proc `bind`*(w: Webview; name: string; fn: BindHandler) =
  ## Exposes `fn` as a global async JavaScript function called `name`.
  ## `fn` receives the JSON array of arguments passed from JavaScript and
  ## must return a `JsonNode`, which becomes the value the JS Promise
  ## resolves to. Exceptions raised by `fn` are caught and turned into a
  ## rejected JS Promise instead of crashing the application.
  let id = nextHandlerId
  inc nextHandlerId
  bindHandlers[id] = BindEntry(w: w, fn: fn)
  checkError webview_bind(w.handle, name.cstring, cast[pointer](bindTrampoline),
                          cast[pointer](id)),
             "webview_bind"

proc unbind*(w: Webview; name: string) =
  ## Removes a binding previously created with `bind`.
  checkError webview_unbind(w.handle, name.cstring), "webview_unbind"
