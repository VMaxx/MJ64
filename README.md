# MJ64
Windows Mouse Jiggler in NASM assembly format

Some paths are likely to vary depending on your tools.
to build:
rc /nologo /i"C:\Program Files\Microsoft Visual Studio\18\Community\SDK\ScopeCppSDK\vc15\SDK\include\um" /i"C:\Program Files\Microsoft Visual Studio\18\Community\SDK\ScopeCppSDK\vc15\SDK\include\shared" /fo MJ64res.res MJ64res.rc
"C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64\cvtres.exe" /machine:X64 MJ64res.res 
nasm.exe -f win64 -g -F cv8 MJ64.asm -o MJ64.obj
"C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64\link" MJ64.obj MJ64res.obj kernel32.lib user32.lib shell32.lib /SUBSYSTEM:WINDOWS /ENTRY:start /LARGEADDRESSAWARE:NO /LIBPATH:"C:\Program Files\Microsoft Visual Studio\18\Community\SDK\ScopeCppSDK\vc15\SDK\lib"
