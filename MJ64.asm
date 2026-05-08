;=====================================================================
;  MJ64.asm
;  64-bit Windows (NASM syntax)
;  -------------------------------------------------------------
;  * Tray-icon program that “moves” the mouse once per second.
;  * The mouse move is performed with SendInput (dx=0, dy=0) instead of
;    GetCursorPos/SetCursorPos.
;  * right-click on the tray icon quits app
;  * Coffee icon, because it keeps your screen awake.
;=====================================================================

        bits 64

;---------------------------------------------------------------------
;  Imports – Windows-x64 calling convention
;---------------------------------------------------------------------
        extern  GetLastError
        extern  RegisterClassExW
        extern  CreateWindowExW
        extern  DefWindowProcW
        extern  LoadIconW
        extern  LoadCursorW
        extern  Shell_NotifyIconW
        extern  GetModuleHandleW
        extern  SetTimer
        extern  KillTimer
        extern  GetMessageW
        extern  TranslateMessage
        extern  DispatchMessageW
        extern  PostQuitMessage
        extern  DestroyWindow
        extern  ExitProcess
        extern  SetThreadExecutionState
        extern  SendInput               

;---------------------------------------------------------------------
;  Constants
;---------------------------------------------------------------------
%define NIM_ADD       0x00000000
%define NIM_MODIFY    0x00000001
%define NIM_DELETE    0x00000002

%define NIF_MESSAGE   0x00000001
%define NIF_ICON      0x00000002
%define NIF_TIP       0x00000004

%define WM_APP        0x8000
%define LM_MSG_TRAY   (WM_APP + 1)

%define WM_TIMER      0x0113
%define WM_DESTROY    0x0002
%define WM_RBUTTONUP  0x0205

%define WS_OVERLAPPEDWINDOW 0x00CF0000   ; hidden window – no WS_VISIBLE
%define SW_HIDE            0

%define NOTIFYICONDATA_SIZE 956          ; current size of NOTIFYICONDATAW on x64

%define IDC_ARROW          32512        ; MAKEINTRESOURCE(IDC_ARROW)
%define IDI_APPLICATION    32512        ; MAKEINTRESOURCE(IDI_APPLICATION)
%define IDI_TRAY_ICON        101       ; our own icon resource (if any)

%define ES_CONTINUOUS        0x80000000
%define ES_DISPLAY_REQUIRED 0x00000002

; SendInput-related constants (new)
%define INPUT_MOUSE           0
%define MOUSEEVENTF_MOVE     0x0001
%define INPUT_SIZE           40      ; sizeof(INPUT) on x64

;---------------------------------------------------------------------
;  Data – Unicode strings (wide chars, zero-terminated)
;---------------------------------------------------------------------
section .data
    classNameW  dw 'T','r','a','y','I','c','o','n','C','l','a','s','s',0
    tipTextW    dw 'M','o','u','s','e',' ','m','o','v','e','r',0

;---------------------------------------------------------------------
;  BSS – runtime data
;---------------------------------------------------------------------
section .bss
    ; WNDCLASSEXW (80 bytes) + NOTIFYICONDATAW (956 bytes) + MSG (64 bytes)
    wndclass        resb 80
    notifydata      resb NOTIFYICONDATA_SIZE
    hInst           resq 1
    hWnd            resq 1
    iconHandle      resq 1
    msg             resb 64

    ; -----------------------------------------------------------------
    ;  INPUT structure used by SendInput (single entry, 40 bytes)
    ; -----------------------------------------------------------------
    send_input      resb INPUT_SIZE

;---------------------------------------------------------------------
;  Window procedure – forwards everything else to DefWindowProcW
;---------------------------------------------------------------------
section .text
global  WinProc
WinProc:
    ; RCX = hWnd, RDX = uMsg, R8 = wParam, R9 = lParam
    mov     eax, edx                ; low-32 of uMsg
    cmp     eax, WM_TIMER
    je      .handle_timer
    cmp     eax, LM_MSG_TRAY
    je      .handle_tray
    cmp     eax, WM_DESTROY
    je      .handle_destroy

    ; all other messages ? default processing
    jmp     DefWindowProcW

.handle_timer:
    ; ---------------------------------------------------------------
    ;  Send a dummy mouse input (dx=0, dy=0) – resets the idle timer.
    ; ---------------------------------------------------------------
    mov     ecx, 1                  ; cInputs = 1
    lea     rdx, [send_input]       ; LPINPUT pInputs
    mov     r8d, INPUT_SIZE         ; cbSize = sizeof(INPUT)

    sub     rsp, 28h                ; shadow space + alignment
    call    SendInput
    add     rsp, 28h

    xor     eax, eax                ; LRESULT = 0
    ret

.handle_tray:
    ; lParam (R9) = mouse message (e.g. WM_RBUTTONUP)
    mov     eax, r9d                ; low-32 of lParam
    cmp     eax, WM_RBUTTONUP
    je      .quit_app
    xor     eax, eax                ; ignore other clicks
    ret

.quit_app:
    ; ---------------------------------------------------------------
    ;  Remove tray icon, post quit message
    ; ---------------------------------------------------------------
    mov     ecx, NIM_DELETE
    lea     rdx, [notifydata]
    sub     rsp, 28h
    call    Shell_NotifyIconW
    add     rsp, 28h

    xor     ecx, ecx                ; ExitCode = 0
    call    PostQuitMessage

    xor     eax, eax                ; LRESULT = 0
    ret

.handle_destroy:
    ; Window is being destroyed ? quit
    xor     ecx, ecx
    call    PostQuitMessage
    xor     eax, eax
    ret

;---------------------------------------------------------------------
;  Entry point – start (no CRT)
;---------------------------------------------------------------------
global  start
start:
    ; ---------------------------------------------------------------
    ;  Prevent Windows from sleeping while we run
    ; ---------------------------------------------------------------
    mov     ecx, ES_CONTINUOUS | ES_DISPLAY_REQUIRED
    call    SetThreadExecutionState          ; returns previous state in RAX

    ; ---------------------------------------------------------------
    ;  1) Get a real HINSTANCE for this module
    ; ---------------------------------------------------------------
    sub     rsp, 28h
    xor     rcx, rcx                ; GetModuleHandleW(NULL)
    call    GetModuleHandleW
    add     rsp, 28h
    mov     [hInst], rax

    ; ---------------------------------------------------------------
    ;  2) Zero-initialize a WNDCLASSEXW (80 bytes)
    ; ---------------------------------------------------------------
    lea     rdi, [wndclass]
    xor     eax, eax
    mov     ecx, 80/8
    rep     stosq

    ; Fill the fields we actually need
    mov     dword [wndclass+0], 80                ; cbSize
    mov     rax, WinProc
    mov     [wndclass+8], rax                     ; lpfnWndProc
    mov     rax, [hInst]
    mov     [wndclass+24], rax                    ; hInstance
    lea     rax, [classNameW]
    mov     [wndclass+64], rax                    ; lpszClassName

    ; ---------------------------------------------------------------
    ;  3) Load default icon (IDI_TRAY_ICON) and cursor (IDC_ARROW)
    ; ---------------------------------------------------------------
    ; LoadIconW
    sub     rsp, 28h
    mov     rcx, [hInst]               ; hInstance = our module (or NULL)
    mov     edx, IDI_TRAY_ICON
    call    LoadIconW
    add     rsp, 28h
    mov     [iconHandle], rax
    mov     [wndclass+32], rax        ; hIcon

    ; LoadCursorW
    sub     rsp, 28h
    xor     rcx, rcx
    mov     edx, IDC_ARROW
    call    LoadCursorW
    add     rsp, 28h
    mov     [wndclass+40], rax        ; hCursor

    ; ---------------------------------------------------------------
    ;  4) Register the window class
    ; ---------------------------------------------------------------
    lea     rcx, [wndclass]
    sub     rsp, 28h
    call    RegisterClassExW
    add     rsp, 28h

    ; ---------------------------------------------------------------
    ;  5) Create a hidden top-level window (no WS_VISIBLE)
    ; ---------------------------------------------------------------
    sub     rsp, 28h
    xor     rcx, rcx                 ; dwExStyle = 0
    lea     rdx, [classNameW]        ; lpClassName (wide)
    xor     r8, r8                   ; lpWindowName = NULL
    mov     r9d, WS_OVERLAPPEDWINDOW ; dwStyle (no WS_VISIBLE)

    ; Stack arguments 5-8 (after the 32-byte shadow area)
    mov     qword [rsp+20h], 0       ; X
    mov     qword [rsp+28h], 0       ; Y
    mov     qword [rsp+30h], 0       ; nWidth
    mov     qword [rsp+38h], 0       ; nHeight
    mov     qword [rsp+40h], 0       ; hWndParent = NULL
    mov     qword [rsp+48h], 0       ; hMenu = NULL
    mov     rax, [hInst]
    mov     qword [rsp+50h], rax     ; hInstance
    mov     qword [rsp+58h], 0       ; lpParam = NULL
    call    CreateWindowExW
    add     rsp, 28h

    mov     [hWnd], rax               ; keep the window handle

    ; ---------------------------------------------------------------
    ;  6) Build NOTIFYICONDATAW (zeroed, then fill the fields we need)
    ; ---------------------------------------------------------------
    lea     rdi, [notifydata]
    xor     eax, eax
    mov     ecx, NOTIFYICONDATA_SIZE/8
    rep     stosq                         ; clear struct

    mov     dword [notifydata+0], NOTIFYICONDATA_SIZE   ; cbSize
    mov     rax, [hWnd]
    mov     [notifydata+8], rax                       ; hWnd
    mov     dword [notifydata+16], 1                  ; uID (any non-zero)
    mov     dword [notifydata+20], NIF_MESSAGE | NIF_ICON | NIF_TIP
    mov     dword [notifydata+24], LM_MSG_TRAY
    mov     rax, [iconHandle]
    mov     [notifydata+32], rax                      ; hIcon

    ; Copy tip text – szTip (WCHAR[128]) starts at offset 40
    lea     rsi, [tipTextW]
    lea     rdi, [notifydata+40]
    mov     rcx, 12                                   ; 11 chars + NUL = 12 WORDs
    rep     movsw

    ; ---------------------------------------------------------------
    ;  7) Add the tray icon (Shell_NotifyIconW, NIM_ADD)
    ; ---------------------------------------------------------------
    mov     ecx, NIM_ADD
    lea     rdx, [notifydata]
    sub     rsp, 28h
    call    Shell_NotifyIconW
    add     rsp, 28h

    ; ---------------------------------------------------------------
    ;  8) Initialise the SENDINPUT buffer (one INPUT record)
    ; ---------------------------------------------------------------
    lea     rdi, [send_input]          ; destination address
    xor     eax, eax
    mov     ecx, INPUT_SIZE/8
    rep     stosq                     ; zero the whole 40-byte struct

    mov     dword [send_input], INPUT_MOUSE          ; type = INPUT_MOUSE
    ; The Union part (MOUSEINPUT) starts at offset 8.
    ; Offsets (relative to start of INPUT):
    ;   8  LONG  dx
    ;  12  LONG  dy
    ;  16  DWORD mouseData
    ;  20  DWORD dwFlags     ? set this
    ;  24  DWORD time
    ;  28  ULONGLONG dwExtraInfo
    mov     dword [send_input+20], MOUSEEVENTF_MOVE ; dwFlags = MOVE (dx=dy=0)

    ; ---------------------------------------------------------------
    ;  9) Create a 1-second timer that drives the dummy input
    ; ---------------------------------------------------------------
    mov     rcx, [hWnd]                ; HWND
    mov     edx, 1                     ; timer ID (any non-zero)
    mov     r8d, 1000                  ; 1000 ms interval
    xor     r9, r9                     ; lpTimerFunc = NULL ? WM_TIMER
    sub     rsp, 28h
    call    SetTimer
    add     rsp, 28h
    ; (Result = timer ID – we don’t need it further)

    ; ---------------------------------------------------------------
    ; 10) Main message loop
    ; ---------------------------------------------------------------
msg_loop:
    sub     rsp, 28h
    lea     rcx, [msg]                ; LPMSG
    xor     rdx, rdx                  ; hWnd = NULL (receive all messages)
    xor     r8, r8                    ; wMsgFilterMin = 0
    xor     r9, r9                    ; wMsgFilterMax = 0
    call    GetMessageW
    add     rsp, 28h

    test    eax, eax
    jz      .msg_loop_exit            ; WM_QUIT ? GetMessage returned 0

    sub     rsp, 28h
    lea     rcx, [msg]
    call    TranslateMessage
    add     rsp, 28h

    sub     rsp, 28h
    lea     rcx, [msg]
    call    DispatchMessageW
    add     rsp, 28h

    jmp     msg_loop

.msg_loop_exit:
    ; ---------------------------------------------------------------
    ; 11) Clean-up – remove tray icon (just in case)
    ; ---------------------------------------------------------------
    mov     ecx, NIM_DELETE
    lea     rdx, [notifydata]
    sub     rsp, 28h
    call    Shell_NotifyIconW
    add     rsp, 28h

    ; Destroy the hidden window (optional – OS will clean up anyway)
    mov     rcx, [hWnd]
    sub     rsp, 28h
    call    DestroyWindow
    add     rsp, 28h

    ; ---------------------------------------------------------------
    ; 12) Exit the process
    ; ---------------------------------------------------------------
    xor     ecx, ecx                  ; exit code 0
    call    ExitProcess
