Set WshShell = CreateObject("WScript.Shell")
Set Fso = CreateObject("Scripting.FileSystemObject")

' Chay watch-skills.ps1 o che do an (khong hien cua so PowerShell).
' Duong dan duoc tinh tu vi tri cua file nay, nen repo co the duoc clone o bat ky dau.
scriptDir = Fso.GetParentFolderName(WScript.ScriptFullName)
WshShell.CurrentDirectory = Fso.GetParentFolderName(scriptDir)

WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "\watch-skills.ps1""", 0, False

Set Fso = Nothing
Set WshShell = Nothing
