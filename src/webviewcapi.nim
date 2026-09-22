## Low-level bindings to the C API of https://github.com/webview/webview
## (the ONLY upstream library used by this project - no other webview
## wrapper or GUI toolkit).
##
## This module is a thin, literal translation of the C declarations found
## in `core/include/webview/webview.h`. It adds no behaviour of its own:
## every exported symbol maps 1:1 to its C counterpart, so it can be
## checked line-by-line against the upstream header. The idiomatic,
## "batteries included" Nim API is built on top of this module, in
## `webview.nim`.
##
## Build requirements
## -------------------
## * `webview/webview.h` must be reachable on the C/C++ include path
##   (see `config.nims` and the project README - `nimble vendor` vendors
##   it automatically from the upstream repository).
## * The program must be compiled with Nim's C++ backend (`nim cpp`, or
##   `--backend:cpp`, already configured in `config.nims`), because the
##   C API of webview/webview is implemented *inline* in C++ once the
##   header is consumed from a C++ translation unit - this avoids having
##   to separately build and link `webview::core_static`/`core_shared`.

const
  WebviewLib* = when defined(windows):
                 "./winOS/webview.dll"
               elif defined(macosx):
                 "./macOS/webview.dylib"
               else:
                 "./linOS/webview.so"

type
  WebviewT* = pointer
    ## Opaque handle to a webview instance (`webview_t` in the C header).

  WebviewErrorT* {.size: sizeof(cint).} = enum
    ## Mirrors `webview_error_t`. Values match the C enum exactly. This is
    ## a plain Nim enum (not `importc`'d): Nim automatically inserts the
    ## needed cast when a call's *return value* is assigned to a
    ## differently-named-but-layout-compatible enum type, so no special
    ## handling is needed here (unlike `WebviewHintT` below, which is
    ## passed as an *argument* - see the note on `webview_set_size`).
    weMissingDependency = -5 ## WEBVIEW_ERROR_MISSING_DEPENDENCY
    weCanceled          = -4 ## WEBVIEW_ERROR_CANCELED
    weInvalidState      = -3 ## WEBVIEW_ERROR_INVALID_STATE
    weInvalidArgument   = -2 ## WEBVIEW_ERROR_INVALID_ARGUMENT
    weUnspecified       = -1 ## WEBVIEW_ERROR_UNSPECIFIED
    weOk                = 0  ## WEBVIEW_ERROR_OK
    weDuplicate         = 1  ## WEBVIEW_ERROR_DUPLICATE
    weNotFound          = 2  ## WEBVIEW_ERROR_NOT_FOUND

  WebviewHintT* {.size: sizeof(cint).} = enum
    ## Mirrors `webview_hint_t`, used by `webview_set_size`.
    whNone  = 0 ## WEBVIEW_HINT_NONE  - width/height are the default size
    whMin   = 1 ## WEBVIEW_HINT_MIN   - width/height are minimum bounds
    whMax   = 2 ## WEBVIEW_HINT_MAX   - width/height are maximum bounds
    whFixed = 3 ## WEBVIEW_HINT_FIXED - window size can't be changed by the user

  WebviewNativeHandleKindT* {.size: sizeof(cint).} = enum
    ## Mirrors `webview_native_handle_kind_t`, used by
    ## `webview_get_native_handle`.
    wnhkUiWindow          = 0 ## Top-level window handle.
    wnhkUiWidget          = 1 ## Browser widget handle.
    wnhkBrowserController = 2 ## Browser controller handle.

  WebviewDispatchFn* = proc (w: WebviewT; arg: pointer) {.cdecl.}
    ## Callback signature required by `webview_dispatch`.

  WebviewBindFn* = proc (id, req: cstring; arg: pointer) {.cdecl.}
    ## Callback signature required by `webview_bind`. `req` is a JSON
    ## array (as text) holding the arguments passed from JavaScript.

proc webview_create*(debug: cint = 0; window: pointer = nil): WebviewT
  {.importc: "webview_create", dynlib: WebviewLib, cdecl.}
  ## Creates a new webview instance. Returns `nil` on failure.

proc webview_destroy*(w: WebviewT): WebviewErrorT
  {.importc: "webview_destroy", dynlib: WebviewLib, cdecl.}
  ## Destroys a webview instance and closes its native window.

proc webview_run*(w: WebviewT): WebviewErrorT
  {.importc: "webview_run", dynlib: WebviewLib, cdecl.}
  ## Runs the main/UI event loop until it is terminated.

proc webview_terminate*(w: WebviewT): WebviewErrorT
  {.importc: "webview_terminate", dynlib: WebviewLib, cdecl.}
  ## Stops the event loop started by `webview_run`.

proc webview_dispatch*(w: WebviewT; fn: WebviewDispatchFn;
                        arg: pointer = nil): WebviewErrorT
  {.importc: "webview_dispatch", dynlib: WebviewLib, cdecl.}
  ## Schedules `fn` to run on the event-loop thread.

proc webview_get_window*(w: WebviewT): pointer
  {.importc: "webview_get_window", dynlib: WebviewLib, cdecl.}
  ## Returns the native window handle.

proc webview_get_native_handle*(w: WebviewT;
                                 kind: WebviewNativeHandleKindT): pointer
  {.importc: "webview_get_native_handle", dynlib: WebviewLib, cdecl.}
  ## Returns a native handle of the requested kind.

proc webview_set_title*(w: WebviewT; title: cstring): WebviewErrorT
  {.importc: "webview_set_title", dynlib: WebviewLib, cdecl.}
  ## Sets the native window title.

proc webview_set_size*(w: WebviewT; width, height: cint; hints: cint = 0): WebviewErrorT
  {.importc: "webview_set_size", dynlib: WebviewLib,.}
  ## Sets the native window size, optionally with min/max/fixed hints.
  ## `hints` is a plain `cint` (see `WebviewHintT`); the `importcpp`
  ## pattern above inserts the C-style cast to the real `webview_hint_t`
  ## C++ enum type directly into the call expression, since C++ never
  ## implicitly converts a plain integer into an enum-typed parameter.

proc webview_navigate*(w: WebviewT; url: cstring): WebviewErrorT
  {.importc: "webview_navigate", dynlib: WebviewLib, cdecl.}
  ## Navigates to `url` (a regular URL or a properly encoded data: URI).

proc webview_set_html*(w: WebviewT; html: cstring): WebviewErrorT
  {.importc: "webview_set_html", dynlib: WebviewLib, cdecl.}
  ## Loads `html` directly as the page content.

proc webview_init*(w: WebviewT; js: cstring): WebviewErrorT
  {.importc: "webview_init", dynlib: WebviewLib, cdecl.}
  ## Injects JavaScript that runs before any other script on every page
  ## load (before `window.onload`).

proc webview_eval*(w: WebviewT; js: cstring): WebviewErrorT
  {.importc: "webview_eval", dynlib: WebviewLib, cdecl.}
  ## Evaluates arbitrary JavaScript in the page. Evaluation is
  ## asynchronous and the result of the expression is discarded; use
  ## `webview_bind`/`webview_return` to get a result back into Nim.

proc webview_bind*(w: WebviewT; name: cstring; fn: pointer;
                    arg: pointer = nil): WebviewErrorT
  {.importc: "webview_bind", dynlib: WebviewLib .}
  ## Binds a native callback so that it appears as a global async
  ## JavaScript function called `name`. `fn` must be a `{.cdecl.}` Nim
  ## proc matching `WebviewBindFn`'s signature, passed via
  ## `cast[pointer](myProc)`.
  ##
  ## `fn` is typed as a plain `pointer` (rather than `WebviewBindFn`)
  ## because Nim's `cstring` compiles to a non-const `char*`, while the
  ## real callback parameters are `const char*`; C++ requires function
  ## pointer *types* to match exactly (unlike plain arguments, where
  ## `char*` -> `const char*` converts implicitly), so the `importcpp`
  ## pattern above inserts the necessary C-style cast directly into the
  ## call expression (safe: only the `const` qualifier differs, the
  ## calling convention and memory layout are identical).

proc webview_unbind*(w: WebviewT; name: cstring): WebviewErrorT
  {.importc: "webview_unbind", dynlib: WebviewLib, cdecl.}
  ## Removes a binding created with `webview_bind`.

proc webview_return*(w: WebviewT; id: cstring; status: cint;
                      resultJson: cstring): WebviewErrorT
  {.importc: "webview_return", dynlib: WebviewLib, cdecl.}
  ## Responds to a binding call from the JavaScript side. `status` zero
  ## means success; `resultJson` must be valid JSON (or an empty string
  ## for JavaScript `undefined`).
