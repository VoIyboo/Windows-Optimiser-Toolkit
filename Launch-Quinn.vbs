Option Explicit

Dim shell
Dim scriptDir
Dim command

Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

command = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "\run-local.ps1"""
shell.Run command, 0, False
