Option Explicit

Dim shell, files, result
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")

' Keep the extraction path out of Run's environment-variable expansion.
shell.CurrentDirectory = files.GetParentFolderName(WScript.ScriptFullName)
result = shell.Run("""%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "".\run-local.ps1""", 0, True)
If result <> 0 Then
    WScript.Echo "Quinn could not start. Extract the complete toolkit, then open it again. For startup details, run run-local.ps1 from PowerShell."
End If
WScript.Quit result
