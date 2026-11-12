@echo off
rem Starts Sara with its door open, so a notebook or a script on this machine
rem can attach to it with sara.py, which sits beside this file in the zip.
rem
rem The door listens on the loopback address only, and Sara writes the port
rem and its token to one known file while it listens:
rem
rem     %APPDATA%\Godot\app_userdata\Sara\door.json
rem
rem sara.py reads that file to attach, and Sara removes it when it closes.
rem Plain sara.exe opens no door and writes no such file.
rem
rem Godot hands Sara only the arguments after the "--", so --agent-door stays
rem after it, and anything given to this launcher, a painting to open, follows.
start "" "%~dp0sara.exe" -- --agent-door %*
