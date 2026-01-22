#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

global LAUNCHER_VERSION := "1.0.0"

; ================= AUTHENTICATION GLOBALS =================
global WORKER_URL := "https://empty-band-2be2.lewisjenkins558.workers.dev"
global SESSION_TOKEN_FILE := ""
global DISCORD_URL := "https://discord.gg/PQ85S32Ht8"
global WEBHOOK_URL := ""

; Credential & Session Files (kept for compatibility, but no master key stored)
global DISCORD_ID_FILE := ""
global DISCORD_BAN_FILE := ""
global ADMIN_DISCORD_FILE := ""
global HWID_BAN_FILE := ""
global MACHINE_BAN_FILE := ""
global HWID_BINDING_FILE := ""

; Login Settings
global MAX_ATTEMPTS := 10
global LOCKOUT_FILE := A_Temp "\.lockout"

; Auth State
global gLoginGui := 0
global KEY_HISTORY := []
global APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content"
global SECURE_VAULT := ""
global BASE_DIR := ""
global VERSION_FILE := ""
global ICON_DIR := ""
global MANIFEST_URL := ""
global MACHINE_KEY := ""
global MACRO_LAUNCHER_PATH := ""

global COLORS := {
    bg: "0x0a0e14",
    bgLight: "0x13171d",
    card: "0x161b22",
    cardHover: "0x1c2128",
    accent: "0xd29922",
    accentHover: "0x2ea043",
    accentAlt: "0x1f6feb",
    text: "0xe6edf3",
    textDim: "0x7d8590",
    border: "0x21262d",
    success: "0x238636",
    warning: "0xd29922",
    danger: "0xda3633"
}

; =========================================
InitializeSecureVault()
SetTaskbarIcon()
CheckLoginAppUpdate()

did := ReadDiscordId()
CheckLockout()
EnsureDiscordId()

if !ValidateNotBanned() {
    ShowBanMessage()
    ExitApp
}

if CheckSession() {
    if !ValidateNotBanned() {
        ShowBanMessage()
        ExitApp
    }
    StartSessionWatchdog()
    LaunchMainApp()
    ExitApp
}

CreateLoginGui()
return

; ============= SECURITY FUNCTIONS =============

InitializeSecureVault() {
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR, VERSION_FILE, MACHINE_KEY
    global DISCORD_ID_FILE, DISCORD_BAN_FILE, ADMIN_DISCORD_FILE
    global HWID_BINDING_FILE, HWID_BAN_FILE, MACHINE_BAN_FILE
    global MANIFEST_URL, MACRO_LAUNCHER_PATH, SESSION_TOKEN_FILE
    
    MACHINE_KEY := GetOrCreatePersistentKey()
    
    dirHash := HashString(MACHINE_KEY . A_ComputerName)
    APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content\{" SubStr(dirHash, 1, 8) "}"
    SECURE_VAULT := APP_DIR "\{" SubStr(dirHash, 9, 8) "}"
    BASE_DIR := SECURE_VAULT "\dat"
    ICON_DIR := SECURE_VAULT "\res"
    VERSION_FILE := SECURE_VAULT "\~ver.tmp"
    MANIFEST_URL := DecryptManifestUrl()
    
    ; Set file paths
    MACRO_LAUNCHER_PATH := SECURE_VAULT "\MacroLauncher.ahk"
    SESSION_TOKEN_FILE := SECURE_VAULT "\.session_token"
    DISCORD_ID_FILE := SECURE_VAULT "\discord_id.txt"
    DISCORD_BAN_FILE := SECURE_VAULT "\banned_discord_ids.txt"
    ADMIN_DISCORD_FILE := SECURE_VAULT "\admin_discord_ids.txt"
    HWID_BAN_FILE := SECURE_VAULT "\banned_hwids.txt"
    MACHINE_BAN_FILE := SECURE_VAULT "\.machine_banned"
    HWID_BINDING_FILE := SECURE_VAULT "\.hwid_bind"
    
    try {
        DirCreate APP_DIR
        DirCreate SECURE_VAULT
        DirCreate BASE_DIR
        DirCreate ICON_DIR
        
        RunWait 'attrib +h +s +r "' APP_DIR '"', , "Hide"
        RunWait 'attrib +h +s +r "' SECURE_VAULT '"', , "Hide"
        RunWait 'attrib +h +s +r "' BASE_DIR '"', , "Hide"
        RunWait 'attrib +h +s +r "' ICON_DIR '"', , "Hide"
        
        RunWait 'icacls "' SECURE_VAULT '" /inheritance:r /grant:r "' A_UserName '":F', , "Hide"
    } catch as err {
        MsgBox "Failed to initialize secure vault: " err.Message, "Security Error", "Icon!"
        ExitApp
    }
    
    EnsureVersionFile()
    
    ; Extract MacroLauncher if it doesn't exist
    if !FileExist(MACRO_LAUNCHER_PATH) {
        ExtractMacroLauncher()
        LoadWebhookUrl()
        ; ADD THIS DEBUG CODE:
if (WEBHOOK_URL = "") {
    MsgBox "⚠️ WEBHOOK_URL is EMPTY!`n`nWebhook notifications will not work.", "Debug", "Icon! T5000"
} else {
    MsgBox "✅ Webhook loaded:`n`n" WEBHOOK_URL, "Debug", "Iconi T5000"
}
; END DEBUG CODE
    }
}

; ========== WEBHOOK FUNCTIONS ==========

LoadWebhookUrl() {
    global WEBHOOK_URL, MANIFEST_URL
    
    try {
        tmpManifest := A_Temp "\manifest_webhook.json"
        
        if SafeDownload(MANIFEST_URL, tmpManifest, 10000) {
            json := FileRead(tmpManifest, "UTF-8")
            
            if RegExMatch(json, '"webhook_url"\s*:\s*"([^"]+)"', &m) {
                WEBHOOK_URL := Trim(m[1])
            }
            
            try FileDelete tmpManifest
        }
    } catch {
    }
}

SendWebhook(title, description, color := 3447003, fields := "") {
    global WEBHOOK_URL
    
    ; ADD THIS DEBUG
    if (WEBHOOK_URL = "") {
        MsgBox "Cannot send webhook - WEBHOOK_URL is empty!", "Debug", "Icon!"
        return false
    }
    ; END DEBUG
    
    try {
        timestamp := FormatTime(, "yyyy-MM-ddTHH:mm:ssZ")
        
        embed := '{"embeds":[{"title":"' JsonEscape(title) '","description":"' JsonEscape(description) '","color":' color ',"timestamp":"' timestamp '"'
        
        if (fields != "") {
            embed .= ',"fields":[' fields ']'
        }
        
        embed .= ',"footer":{"text":"AHK Vault Login System"}}]}'
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 3000, 3000)
        req.Open("POST", WEBHOOK_URL, false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(embed)
        
        ; ADD THIS DEBUG
        MsgBox "✅ Webhook sent!`nStatus: " req.Status, "Debug", "Iconi T2000"
        ; END DEBUG
        
        return true
    } catch as err {
        ; ADD THIS DEBUG
        MsgBox "❌ Webhook error:`n`n" err.Message, "Debug", "Icon!"
        ; END DEBUG
        return false
    }
}

SendLoginSuccessNotification(username, discordId) {
    computerName := A_ComputerName
    userName := A_UserName
    hwid := GetHardwareId()
    ip := GetPublicIP()
    
    fields := '{"name":"Username","value":"' JsonEscape(username) '","inline":true},'
            . '{"name":"Discord ID","value":"' discordId '","inline":true},'
            . '{"name":"Computer","value":"' computerName '","inline":true},'
            . '{"name":"User","value":"' userName '","inline":true},'
            . '{"name":"HWID","value":"' hwid '","inline":true},'
            . '{"name":"IP Address","value":"' ip '","inline":true}'
    
    SendWebhook("✅ Login Successful", username " logged in successfully", 3066993, fields)
}

SendLoginFailNotification(username, reason) {
    computerName := A_ComputerName
    userName := A_UserName
    hwid := GetHardwareId()
    ip := GetPublicIP()
    
    fields := '{"name":"Username","value":"' JsonEscape(username) '","inline":true},'
            . '{"name":"Reason","value":"' JsonEscape(reason) '","inline":true},'
            . '{"name":"Computer","value":"' computerName '","inline":true},'
            . '{"name":"User","value":"' userName '","inline":true},'
            . '{"name":"HWID","value":"' hwid '","inline":true},'
            . '{"name":"IP Address","value":"' ip '","inline":true}'
    
    SendWebhook("❌ Login Failed", "Failed login attempt", 15158332, fields)
}

SendBanNotification(discordId, hwid, reason := "banned") {
    computerName := A_ComputerName
    
    fields := '{"name":"Discord ID","value":"' discordId '","inline":true},'
            . '{"name":"HWID","value":"' hwid '","inline":true},'
            . '{"name":"Reason","value":"' JsonEscape(reason) '","inline":true},'
            . '{"name":"Computer","value":"' computerName '","inline":true}'
    
    SendWebhook("🚫 Account Banned", "User attempted to access while banned", 15158332, fields)
}

SendLockoutNotification(username) {
    computerName := A_ComputerName
    userName := A_UserName
    ip := GetPublicIP()
    
    fields := '{"name":"Username","value":"' JsonEscape(username) '","inline":true},'
            . '{"name":"Computer","value":"' computerName '","inline":true},'
            . '{"name":"User","value":"' userName '","inline":true},'
            . '{"name":"IP Address","value":"' ip '","inline":true}'
    
    SendWebhook("🔒 Account Locked", "Too many failed login attempts - account locked for 30 minutes", 15105570, fields)
}

GetPublicIP() {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 3000, 3000)
        req.Open("GET", "https://api.ipify.org", false)
        req.Send()
        return Trim(req.ResponseText)
    } catch {
        return "Unknown"
    }
}

CheckLauncherUpdate() {
    global LAUNCHER_VERSION, MANIFEST_URL
    
    try {
        ; Get manifest
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", MANIFEST_URL, false)
        req.Send()
        
        ; Parse version
        if RegExMatch(req.ResponseText, '"launcher_version"\s*:\s*"([^"]+)"', &v) {
            if (v[1] != LAUNCHER_VERSION) {
                ; Parse URL
                if RegExMatch(req.ResponseText, '"launcher_url"\s*:\s*"([^"]+)"', &u) {
                    ; Download
                    temp := A_Temp "\new.ahk"
                    Download u[1], temp
                    
                    ; Replace & restart
                    bat := 
                    (
                    '@echo off
                    timeout /t 1 > nul
                    copy /y "' temp '" "' A_ScriptFullPath '"
                    start "" "' A_AhkPath '" "' A_ScriptFullPath '"
                    del "' temp '" & del "%~f0"
                    '
                    )
                    
                    FileAppend bat, A_Temp "\u.bat"
                    Run A_Temp "\u.bat", , "Hide"
                    ExitApp
                }
            }
        }
    }
}

CheckLoginAppUpdate() {
    global LAUNCHER_VERSION, MANIFEST_URL
    
    try {
        ; Download manifest
        tmpManifest := A_Temp "\manifest_update_check.json"
        
        if !SafeDownload(NoCacheUrl(MANIFEST_URL), tmpManifest, 15000) {
            return  ; Silently fail - don't block app launch
        }
        
        ; Parse manifest
        json := ""
        try {
            json := FileRead(tmpManifest, "UTF-8")
        } catch {
            return
        }
        
        ; Extract launcher_version and login_url
        manifestVersion := ""
        loginUrl := ""
        
        if RegExMatch(json, '"launcher_version"\s*:\s*"([^"]+)"', &v) {
            manifestVersion := Trim(v[1])
        }
        
        if RegExMatch(json, '"login_url"\s*:\s*"([^"]+)"', &u) {
            loginUrl := Trim(u[1])
        }
        
        ; Check if update needed
        if (manifestVersion = "" || loginUrl = "") {
            return  ; Missing data, skip update
        }
        
        if (VersionCompare(manifestVersion, LAUNCHER_VERSION) <= 0) {
            return  ; Already up to date
        }
        
        ; ===== UPDATE AVAILABLE =====
        choice := MsgBox(
            "🔄 Login App Update Available!`n`n"
            . "Current: v" LAUNCHER_VERSION "`n"
            . "Latest: v" manifestVersion "`n`n"
            . "Update now? (Recommended)",
            "AHK Vault - Update Available",
            "YesNo Iconi"
        )
        
        if (choice = "No") {
            return
        }
        
        ; Download new version
        tmpUpdate := A_Temp "\AHK_Vault_Update.ahk"
        
        ToolTip "Downloading update..."
        
        if !SafeDownload(loginUrl, tmpUpdate, 30000) {
            ToolTip
            MsgBox "Update download failed. Continuing with current version.", "Update Failed", "Icon!"
            return
        }
        
        ToolTip
        
        ; Validate downloaded file
        try {
            content := FileRead(tmpUpdate, "UTF-8")
            
            if (StrLen(content) < 1000) {
                throw Error("Downloaded file too small")
            }
            
            if (!InStr(content, "#Requires AutoHotkey v2.0")) {
                throw Error("Not a valid AHK v2 script")
            }
            
            if (!InStr(content, "LAUNCHER_VERSION")) {
                throw Error("Not the login app")
            }
        } catch as err {
            MsgBox "Update validation failed: " err.Message "`n`nContinuing with current version.", "Update Failed", "Icon!"
            try FileDelete tmpUpdate
            return
        }
        
        ; ===== APPLY UPDATE =====
        try {
            currentScript := A_ScriptFullPath
            backupScript := A_ScriptDir "\AHK_Vault_Login_BACKUP.ahk"
            
            ; Create backup of current version
            if FileExist(currentScript) {
                FileCopy currentScript, backupScript, 1
            }
            
            ; Create batch file to replace script and restart
            batFile := A_Temp "\update_login.bat"
            batContent := 
            (
            '@echo off
            echo Updating AHK Vault Login...
            timeout /t 2 /nobreak >nul
            copy /y "' tmpUpdate '" "' currentScript '"
            timeout /t 1 /nobreak >nul
            start "" "' A_AhkPath '" "' currentScript '"
            del "' tmpUpdate '"
            del "%~f0"
            '
            )
            
            if FileExist(batFile)
                FileDelete batFile
            FileAppend batContent, batFile
            
            ; Show update message
            MsgBox (
                "✅ Update downloaded successfully!`n`n"
                . "The app will restart now to apply the update.`n`n"
                . "New version: v" manifestVersion
            ), "Update Ready", "Iconi T3000"
            
            ; Run update batch and exit
            Run batFile, , "Hide"
            Sleep 500
            ExitApp
            
        } catch as err {
            MsgBox "Failed to apply update: " err.Message "`n`nContinuing with current version.", "Update Failed", "Icon!"
            
            ; Cleanup
            try FileDelete tmpUpdate
            try FileDelete batFile
        }
        
    } catch as err {
        ; Silent fail - don't interrupt app launch
    }
}

VersionCompare(a, b) {
    a := RegExReplace(a, "[^0-9.]", "")
    b := RegExReplace(b, "[^0-9.]", "")
    
    pa := StrSplit(a, ".")
    pb := StrSplit(b, ".")
    
    Loop Max(pa.Length, pb.Length) {
        va := pa.Has(A_Index) ? Integer(pa[A_Index]) : 0
        vb := pb.Has(A_Index) ? Integer(pb[A_Index]) : 0
        
        if (va > vb)
            return 1
        if (va < vb)
            return -1
    }
    
    return 0
}

NoCacheUrl(url) {
    separator := InStr(url, "?") ? "&" : "?"
    return url . separator . "nocache=" . A_TickCount
}

EnsureVersionFile() {
    global VERSION_FILE
    if !FileExist(VERSION_FILE) {
        try FileAppend "0", VERSION_FILE
    }
}

ExtractMacroLauncher() {
    global MACRO_LAUNCHER_PATH, MANIFEST_URL, WORKER_URL
    
    try {
        ; Step 1: Download manifest to get launcher URL
        tmpManifest := A_Temp "\manifest_launcher.json"
        
        if !SafeDownload(MANIFEST_URL, tmpManifest, 15000) {
            MsgBox "Failed to download manifest for launcher.`n`nCheck internet connection.", "Download Error", "Icon!"
            return false
        }
        
        ; Step 2: Parse manifest to get launcher_url
        json := ""
        try {
            json := FileRead(tmpManifest, "UTF-8")
        } catch {
            MsgBox "Failed to read manifest file.", "Error", "Icon!"
            return false
        }
        
        launcherUrl := ""
        
        ; Try to extract launcher_url from manifest
        if RegExMatch(json, '"launcher_url"\s*:\s*"([^"]+)"', &m) {
            launcherUrl := m[1]
        }
        
        ; If not in manifest, construct from worker URL
        if (launcherUrl = "") {
            launcherUrl := WORKER_URL "/download/launcher"
        }
        
        ; Step 3: Download MacroLauncher.ahk
        tmpLauncher := A_Temp "\MacroLauncher_Download.ahk"
        
        ToolTip "Downloading MacroLauncher..."
        
        if !SafeDownload(launcherUrl, tmpLauncher, 30000) {
            ToolTip
            MsgBox "Failed to download MacroLauncher.ahk`n`nURL: " launcherUrl, "Download Error", "Icon!"
            return false
        }
        
        ToolTip
        
        ; Step 4: Verify downloaded file is valid AHK
        try {
            content := FileRead(tmpLauncher, "UTF-8")
            
            ; Check if it's actually an AHK script (must contain #Requires or ; comment at start)
            if (StrLen(content) < 100) {
                throw Error("File too small")
            }
            
            if (!InStr(content, "#Requires") && !InStr(content, "global") && !InStr(content, "Gui(")) {
                throw Error("Not a valid AHK script")
            }
        } catch as err {
            MsgBox "Downloaded file is not a valid AHK script:`n`n" err.Message, "Validation Error", "Icon!"
            return false
        }
        
        ; Step 5: Move to secure vault location
        try {
            if FileExist(MACRO_LAUNCHER_PATH)
                FileDelete MACRO_LAUNCHER_PATH
            
            FileCopy tmpLauncher, MACRO_LAUNCHER_PATH, 1
            
            ; Cleanup temp file
            if FileExist(tmpLauncher)
                FileDelete tmpLauncher
            if FileExist(tmpManifest)
                FileDelete tmpManifest
            
        } catch as err {
            MsgBox "Failed to install MacroLauncher:`n`n" err.Message, "Installation Error", "Icon!"
            return false
        }
        
        return true
        
    } catch as err {
        ToolTip
        MsgBox "MacroLauncher extraction failed:`n`n" err.Message, "Error", "Icon!"
        return false
    }
}

GetOrCreatePersistentKey() {
    regPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo"
    regCurrentKey := "MachineGUID"
    regKeyHistory := "KeyHistory"
    regDateValue := "LastRotation"
    
    global KEY_HISTORY := []
    
    currentDate := A_Now
    shouldRotate := false
    currentKey := ""
    
    try {
        currentKey := RegRead(regPath, regCurrentKey)
        lastRotation := RegRead(regPath, regDateValue)
        
        try {
            historyStr := RegRead(regPath, regKeyHistory)
            if (historyStr) {
                for key in StrSplit(historyStr, "|") {
                    if (key && StrLen(key) >= 32)
                        KEY_HISTORY.Push(key)
                }
            }
        }
        
        daysDiff := DateDiff(currentDate, lastRotation, "Days")
        
        if (daysDiff >= 3)
            shouldRotate := true
    } catch {
        shouldRotate := true
    }
    
    if (shouldRotate || !currentKey || StrLen(currentKey) < 32) {
        if (currentKey && StrLen(currentKey) >= 32) {
            KEY_HISTORY.Push(currentKey)
            
            if (KEY_HISTORY.Length > 10)
                KEY_HISTORY.RemoveAt(1)
        }
        
        newKey := GenerateMachineKey()
        
        try {
            RegWrite newKey, "REG_SZ", regPath, regCurrentKey
            RegWrite currentDate, "REG_SZ", regPath, regDateValue
            
            historyStr := ""
            for key in KEY_HISTORY
                historyStr .= key "|"
            RegWrite historyStr, "REG_SZ", regPath, regKeyHistory
            
            return newKey
        } catch {
            return newKey
        }
    }
    
    return currentKey
}

DateDiff(date1, date2, unit := "Days") {
    d1 := SubStr(date1, 1, 8)
    d2 := SubStr(date2, 1, 8)
    
    y1 := SubStr(d1, 1, 4)
    m1 := SubStr(d1, 5, 2)
    day1 := SubStr(d1, 7, 2)
    
    y2 := SubStr(d2, 1, 4)
    m2 := SubStr(d2, 5, 2)
    day2 := SubStr(d2, 7, 2)
    
    diff := (y1 - y2) * 365 + (m1 - m2) * 30 + (day1 - day2)
    
    return Abs(diff)
}

GenerateMachineKey() {
    hwid := A_ComputerName . A_UserName . A_OSVersion
    
    try {
        cpu := ComObjGet("winmgmts:").ExecQuery("SELECT * FROM Win32_Processor")
        for proc in cpu
            hwid .= proc.ProcessorId
    }
    
    try {
        disk := ComObjGet("winmgmts:").ExecQuery("SELECT * FROM Win32_DiskDrive")
        for d in disk {
            hwid .= d.SerialNumber
            break
        }
    }
    
    key := HashString(hwid)
    loop 100
        key := HashString(key . hwid . A_Index)
    
    return key
}

HashString(str) {
    hash := 0
    for char in StrSplit(str) {
        hash := Mod(hash * 31 + Ord(char), 0xFFFFFFFF)
    }
    return Format("{:08X}", hash)
}

DecryptManifestUrl() {
    encrypted := "68747470733A2F2F7261772E67697468756275736572636F6E74656E742E636F6D2F6C6577697377723"
               . "22F6175746F686F746B65792D73747566662D636861742F6D61696E2F6D616E69666573742E6A736F6E"
    
    url := ""
    pos := 1
    while (pos <= StrLen(encrypted)) {
        hex := SubStr(encrypted, pos, 2)
        url .= Chr("0x" hex)
        pos += 2
    }
    
    return url
}

SetTaskbarIcon() {
    global ICON_DIR
    iconPath := ICON_DIR "\Launcher.png"
    
    try {
        if FileExist(iconPath)
            TraySetIcon(iconPath)
        else
            TraySetIcon("shell32.dll", 3)
    } catch {
    }
}

GetHardwareId() {
    hwid := ""
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for proc in objWMI.ExecQuery("SELECT ProcessorId FROM Win32_Processor") {
            hwid .= proc.ProcessorId
            break
        }
    } catch {
    }
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for board in objWMI.ExecQuery("SELECT SerialNumber FROM Win32_BaseBoard") {
            hwid .= board.SerialNumber
            break
        }
    } catch {
    }
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for bios in objWMI.ExecQuery("SELECT SerialNumber FROM Win32_BIOS") {
            hwid .= bios.SerialNumber
            break
        }
    } catch {
    }
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for disk in objWMI.ExecQuery("SELECT VolumeSerialNumber FROM Win32_LogicalDisk WHERE DeviceID='C:'") {
            hwid .= disk.VolumeSerialNumber
            break
        }
    } catch {
    }
    
    if (hwid = "")
        hwid := A_ComputerName . A_UserName
    
    hash := 0
    loop parse hwid
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    
    return hash
}

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

; ================= BAN & SESSION MANAGEMENT =================

CheckLockout() {
    global LOCKOUT_FILE, COLORS
    if !FileExist(LOCKOUT_FILE)
        return
    
    try {
        lockTime := Trim(FileRead(LOCKOUT_FILE))
        diff := DateDiff(A_Now, lockTime, "Minutes")
        if (diff >= 30) {
            try FileDelete LOCKOUT_FILE
            return
        }
        
        remaining := 30 - diff
        
        lockGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "AHK Vault - Account Locked")
        lockGui.BackColor := COLORS.bg
        lockGui.SetFont("s10 c" COLORS.text, "Segoe UI")
        
        lockGui.Add("Text", "x0 y0 w450 h80 Background" COLORS.danger)
        lockGui.Add("Text", "x0 y15 w450 h50 Center c" COLORS.text " BackgroundTrans", "🔒 ACCOUNT LOCKED").SetFont("s18 bold")
        
        lockGui.Add("Text", "x25 y100 w400 h120 Background" COLORS.card)
        lockGui.Add("Text", "x45 y120 w360 c" COLORS.text " BackgroundTrans", 
            "Too many failed login attempts.`n`n"
            . "Time remaining: " remaining " minutes`n`n"
            . "Contact support if this is a mistake.")
        
        exitBtn := lockGui.Add("Button", "x155 y240 w150 h40 Background" COLORS.danger, "Exit")
        exitBtn.SetFont("s10 bold")
        
        exitBtn.OnEvent("Click", (*) => ExitApp())
        lockGui.OnEvent("Close", (*) => ExitApp())
        
        lockGui.Show("w450 h310 Center")
        WinWaitClose(lockGui.Hwnd)
        
        if FileExist(LOCKOUT_FILE)
            ExitApp
            
    } catch {
        try FileDelete LOCKOUT_FILE
    }
}

EnsureDiscordId() {
    global DISCORD_ID_FILE
    try {
        if FileExist(DISCORD_ID_FILE) {
            id := Trim(FileRead(DISCORD_ID_FILE, "UTF-8"))
            if RegExMatch(id, "^\d{6,30}$")
                return
        }
    } catch {
    }
    
    id := PromptDiscordIdGui()
    if (id = "") {
        MsgBox "Discord ID is required.", "AHK Vault - Required", "Icon! 0x10"
        ExitApp
    }
}

PromptDiscordIdGui() {
    global DISCORD_ID_FILE, COLORS
    
    didGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "AHK Vault - Discord ID Required")
    didGui.BackColor := COLORS.bg
    didGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    didGui.Add("Text", "x0 y0 w550 h70 Background" COLORS.accent)
    didGui.Add("Text", "x20 y20 w510 h30 c" COLORS.text " BackgroundTrans", "Discord ID Required").SetFont("s16 bold")
    
    didGui.Add("Text", "x25 y90 w500 h200 Background" COLORS.card)
    
    didGui.Add("Text", "x45 y110 w460 c" COLORS.text " BackgroundTrans", "Enter your Discord User ID (numbers only):")
    didGui.Add("Text", "x45 y135 w460 c" COLORS.textDim " BackgroundTrans", "How to find: Discord → Settings → Advanced → Enable Developer Mode")
    didGui.Add("Text", "x45 y155 w460 c" COLORS.textDim " BackgroundTrans", "Then: Right-click your profile → Copy User ID")
    
    didEdit := didGui.Add("Edit", "x45 y185 w460 h30 Background" COLORS.bgLight " c" COLORS.text)
    
    copyBtn := didGui.Add("Button", "x45 y230 w140 h35 Background" COLORS.accentAlt, "Copy to Clipboard")
    copyBtn.SetFont("s10")
    saveBtn := didGui.Add("Button", "x365 y230 w140 h35 Background" COLORS.success, "Save & Continue")
    saveBtn.SetFont("s10 bold")
    
    status := didGui.Add("Text", "x45 y305 w460 c" COLORS.textDim " BackgroundTrans", "")
    
    resultId := ""
    
    copyBtn.OnEvent("Click", (*) => (
        A_Clipboard := Trim(didEdit.Value),
        status.Value := (Trim(didEdit.Value) = "" ? "Nothing to copy yet." : "✅ Copied to clipboard!")
    ))
    
    saveBtn.OnEvent("Click", (*) => (
        did := Trim(didEdit.Value),
        (!RegExMatch(did, "^\d{6,30}$")
            ? (status.Value := "❌ Invalid ID. Must be 6-30 digits only.", SoundBeep(700, 120))
            : (resultId := did, didGui.Destroy())
        )
    ))
    
    didGui.OnEvent("Close", (*) => (resultId := "", didGui.Destroy()))
    
    didGui.Show("w550 h340 Center")
    WinWaitClose(didGui.Hwnd)
    
    if (resultId = "")
        return ""
    
    try {
        if FileExist(DISCORD_ID_FILE)
            FileDelete DISCORD_ID_FILE
        FileAppend resultId, DISCORD_ID_FILE
    } catch {
    }
    
    return resultId
}

ReadDiscordId() {
    global DISCORD_ID_FILE
    try if FileExist(DISCORD_ID_FILE)
        return Trim(FileRead(DISCORD_ID_FILE, "UTF-8"))
    return ""
}

ValidateNotBanned() {
    if !CheckServerBanStatus()
        return false

    if IsDiscordBanned()
        return false

    if IsHwidBanned()
        return false

    return true
}

CheckServerBanStatus() {
    global WORKER_URL
    
    hwid := GetHardwareId()
    discordId := ReadDiscordId()
    
    if (discordId = "")
        return false
    
    body := '{"hwid":"' hwid '","discord_id":"' discordId '"}'
    
    try {
        resp := WorkerPostPublic("/check-ban", body)
        
        if RegExMatch(resp, '"banned"\s*:\s*true')
            return false
        
        if !ValidateHwidBinding(hwid, discordId)
            return false
        
        return true
    } catch {
        return !IsDiscordBanned() && !IsMachineBanned()
    }
}

ValidateHwidBinding(hwid, discordId) {
    global WORKER_URL, HWID_BINDING_FILE
    
    body := '{"hwid":"' hwid '","discord_id":"' discordId '"}'
    
    try {
        resp := WorkerPostPublic("/validate-binding", body)
        
        if RegExMatch(resp, '"valid"\s*:\s*false') {
            SaveMachineBan(discordId, "hwid_mismatch")
            return false
        }
        
        try {
            if FileExist(HWID_BINDING_FILE)
                FileDelete HWID_BINDING_FILE
            FileAppend hwid "|" discordId "|" A_Now, HWID_BINDING_FILE
            Run 'attrib +h +s "' HWID_BINDING_FILE '"', , "Hide"
        }
        
        return true
    } catch {
        try {
            if FileExist(HWID_BINDING_FILE) {
                data := FileRead(HWID_BINDING_FILE, "UTF-8")
                parts := StrSplit(data, "|")
                if (parts.Length >= 2) {
                    cachedHwid := Trim(parts[1])
                    cachedDiscordId := Trim(parts[2])
                    
                    if (cachedHwid = hwid && cachedDiscordId = discordId)
                        return true
                }
            }
        }
        
        return true
    }
}

ShowBanMessage() {
    global COLORS, DISCORD_URL
    
    banGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "AHK Vault - Account Banned")
    banGui.BackColor := COLORS.bg
    banGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    banGui.Add("Text", "x0 y0 w500 h80 Background" COLORS.danger)
    banGui.Add("Text", "x0 y15 w500 h50 Center c" COLORS.text " BackgroundTrans", "🚫 ACCOUNT BANNED").SetFont("s20 bold")
    
    banGui.Add("Text", "x25 y100 w450 h250 Background" COLORS.card)
    
    msgText := banGui.Add("Text", "x45 y120 w410 c" COLORS.text " BackgroundTrans", 
        "You've been banned from using AHK Vault.`n`n"
        . "Discord ID: " ReadDiscordId() "`n"
        . "HWID: " GetHardwareId() "`n`n"
        . "If you think this was a mistake, please join our`n"
        . "Discord to contact support.")
    msgText.SetFont("s10")
    
    discordBtn := banGui.Add("Button", "x45 y285 w410 h45 Background" COLORS.accentAlt, "Join Our Discord for Support")
    discordBtn.SetFont("s11 bold")
    discordBtn.OnEvent("Click", (*) => SafeOpenURL(DISCORD_URL))
    
    closeBtn := banGui.Add("Button", "x200 y370 w100 h35 Background" COLORS.danger, "Close")
    closeBtn.SetFont("s10 bold")
    closeBtn.OnEvent("Click", (*) => ExitApp())
    
    banGui.OnEvent("Close", (*) => ExitApp())
    banGui.Show("w500 h430 Center")
    
    WinWaitClose(banGui.Hwnd)
}

IsMachineBanned() {
    global MACHINE_BAN_FILE
    
    if !FileExist(MACHINE_BAN_FILE)
        return false
    
    try {
        data := Trim(FileRead(MACHINE_BAN_FILE, "UTF-8"))
        if (data = "")
            return false
        
        parts := StrSplit(data, "|")
        bannedHwid := (parts.Length >= 2) ? Trim(parts[2]) : ""
        currentHwid := GetHardwareId()
        
        return (bannedHwid != "" && bannedHwid = currentHwid)
    } catch {
        return false
    }
}

SaveMachineBan(discordId := "", reason := "banned") {
    global MACHINE_BAN_FILE
    
    try {
        t := A_Now
        hwid := GetHardwareId()
        did := Trim(discordId)
        
        if FileExist(MACHINE_BAN_FILE)
            FileDelete MACHINE_BAN_FILE
        
        FileAppend t "|" hwid "|" did "|" reason, MACHINE_BAN_FILE
        Run 'attrib +h +s "' MACHINE_BAN_FILE '"', , "Hide"
    } catch {
    }
}

IsDiscordBanned() {
    global DISCORD_BAN_FILE
    if !FileExist(DISCORD_BAN_FILE)
        return false
    
    did := ReadDiscordId()
    if (did = "")
        return false
    
    txt := ""
    try {
        txt := FileRead(DISCORD_BAN_FILE, "UTF-8")
    } catch {
        return false
    }
    
    for line in StrSplit(txt, "`n") {
        if (Trim(line) = did)
            return true
    }
    return false
}

IsHwidBanned() {
    global HWID_BAN_FILE
    if !FileExist(HWID_BAN_FILE)
        return false
    hwid := GetHardwareId()
    
    try {
        txt := FileRead(HWID_BAN_FILE, "UTF-8")
        for line in StrSplit(txt, "`n") {
            if (Trim(line) = hwid)
                return true
        }
    }
    return false
}

CheckSession() {
    global SESSION_TOKEN_FILE, WORKER_URL
    
    if !FileExist(SESSION_TOKEN_FILE)
        return false
    
    try {
        token := Trim(FileRead(SESSION_TOKEN_FILE, "UTF-8"))
        if (token = "")
            return false
        
        ; Verify session with server
        body := '{"session_token":"' JsonEscape(token) '"}'
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("POST", WORKER_URL "/auth/verify", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        if (req.Status != 200)
            return false
        
        resp := req.ResponseText
        if RegExMatch(resp, '"valid"\s*:\s*true')
            return true
        
        ; Session invalid - delete token
        if FileExist(SESSION_TOKEN_FILE)
            FileDelete SESSION_TOKEN_FILE
        
        return false
    } catch {
        return false
    }
}

StartSessionWatchdog() {
    SetTimer(CheckBanStatusPeriodic, 10000)
}

CheckBanStatusPeriodic() {
    if !ValidateNotBanned() {
        try DestroyLoginGui()
        ShowBanMessage()
    }
}

WorkerPostPublic(endpoint, bodyJson) {
    global WORKER_URL
    
    url := RTrim(WORKER_URL, "/") "/" LTrim(endpoint, "/")
    
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("POST", url, false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("User-Agent", "AHK-Vault")
    req.Send(bodyJson)
    
    status := req.Status
    resp := ""
    try resp := req.ResponseText
    
    if (status < 200 || status >= 300)
        throw Error("Worker error " status ": " resp)
    return resp
}

WorkerPostAuth(endpoint, bodyJson) {
    global WORKER_URL, SESSION_TOKEN_FILE
    
    if !FileExist(SESSION_TOKEN_FILE) {
        throw Error("No session token - please login")
    }
    
    token := Trim(FileRead(SESSION_TOKEN_FILE))
    
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("POST", WORKER_URL "/" LTrim(endpoint, "/"), false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("X-Session-Token", token)
    req.SetRequestHeader("User-Agent", "AHK-Vault")
    req.Send(bodyJson)
    
    if (req.Status < 200 || req.Status >= 300) {
        if (req.Status = 401) {
            try FileDelete SESSION_TOKEN_FILE
            MsgBox "Session expired. Please login again."
            CreateLoginGui()
            return ""
        }
        throw Error("Request failed: " req.Status)
    }
    
    return req.ResponseText
}

HashPassword(password) {
    salt := "V1LN_CLAN_2026_SECURE"
    combined := salt . password . salt
    
    hash := 0
    Loop Parse combined
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    
    Loop 10000 {
        hash := Mod(hash * 37 + Ord(SubStr(password, Mod(A_Index, StrLen(password)) + 1, 1)), 2147483647)
    }
    
    return hash
}

SafeDownload(url, out, timeoutMs := 10000) {
    if !url || !out
        return false
    
    try {
        if FileExist(out)
            FileDelete out
        
        Download url, out
        
        startTime := A_TickCount
        while !FileExist(out) {
            if (A_TickCount - startTime > timeoutMs) {
                return false
            }
            Sleep 100
        }
        
        fileSize := 0
        Loop Files, out
            fileSize := A_LoopFileSize
        
        if (fileSize < 100) {
            try FileDelete out
            return false
        }
        
        return true
    } catch {
        return false
    }
}

SafeOpenURL(url) {
    url := Trim(url)
    
    if (!InStr(url, "http://") && !InStr(url, "https://")) {
        MsgBox "Invalid URL: " url, "Error", "Icon!"
        return
    }
    
    try {
        Run url
    } catch as err {
        MsgBox "Failed to open URL: " err.Message, "Error", "Icon!"
    }
}

; ================= LOGIN GUI =================

CreateLoginGui() {
    global COLORS, gLoginGui
    
    gLoginGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "AHK Vault - Login")
    loginGui := gLoginGui
    
    loginGui.BackColor := COLORS.bg
    loginGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    ; Header
    loginGui.Add("Text", "x0 y0 w500 h80 Background" COLORS.accent)
    loginGui.Add("Text", "x0 y15 w500 h50 Center c" COLORS.text " BackgroundTrans", "🔐 AHK VAULT").SetFont("s22 bold")
    
    ; Login Card
    loginGui.Add("Text", "x50 y100 w400 h250 Background" COLORS.card)
    
    loginGui.Add("Text", "x70 y120 w360 h100 Center c" COLORS.text " BackgroundTrans", "Welcome Back").SetFont("s14 bold")
    loginGui.Add("Text", "x70 y150 w360 Center c" COLORS.textDim " BackgroundTrans", "Enter your credentials to continue")
    
    ; Username field
    loginGui.Add("Text", "x70 y190 c" COLORS.text " BackgroundTrans", "Username:")
    usernameEdit := loginGui.Add("Edit", "x70 y210 w360 h35 Background" COLORS.bgLight " c" COLORS.text)
    
    ; Password field
    loginGui.Add("Text", "x70 y260 c" COLORS.text " BackgroundTrans", "Password:")
    passwordEdit := loginGui.Add("Edit", "x70 y280 w360 h35 Password Background" COLORS.bgLight " c" COLORS.text)
    
    ; Status text
    statusText := loginGui.Add("Text", "x70 y325 w360 Center c" COLORS.danger " BackgroundTrans", "")
    
    ; Login button
    loginBtn := loginGui.Add("Button", "x70 y360 w360 h45 Background" COLORS.success, "LOGIN")
    loginBtn.SetFont("s12 bold")
    
    ; Discord link
    discordBtn := loginGui.Add("Button", "x70 y420 w360 h35 Background" COLORS.accentAlt, "Join Our Discord")
    discordBtn.SetFont("s10")
    
    ; Footer
    loginGui.Add("Text", "x0 y475 w500 h30 Center c" COLORS.textDim " BackgroundTrans", "AHK Vault v" LAUNCHER_VERSION)
    
    ; Events
    loginBtn.OnEvent("Click", (*) => AttemptLogin(usernameEdit.Value, passwordEdit.Value, statusText))
    discordBtn.OnEvent("Click", (*) => SafeOpenURL(DISCORD_URL))
    passwordEdit.OnEvent("Change", (*) => statusText.Value := "")
    usernameEdit.OnEvent("Change", (*) => statusText.Value := "")
    
    loginGui.OnEvent("Close", (*) => ExitApp())
    loginGui.Show("w500 h505 Center")
}

AttemptLogin(username, password, statusControl) {
    global SESSION_TOKEN_FILE, MAX_ATTEMPTS, LOCKOUT_FILE

    SendBanNotification(ReadDiscordId(), GetHardwareId(), "viewing_ban_screen")
    if (Trim(username) = "" || Trim(password) = "") {
        statusControl.Value := "Please enter both username and password"
        SoundBeep(700, 120)
        return
    }
    
    static attemptCount := 0
    
    statusControl.Value := "Authenticating..."
    
    try {
        discordId := ReadDiscordId()
        hwid := GetHardwareId()
        passwordHash := HashPassword(password)
        
        body := '{"discord_id":"' JsonEscape(discordId) '","hwid":"' hwid '","username":"' JsonEscape(username) '","password_hash":"' passwordHash '"}'
        
        resp := WorkerPostPublic("/auth/login", body)
        
        ; Check if banned
        if RegExMatch(resp, '"error"\s*:\s*"banned"') {
            statusControl.Value := "Account is banned"
            SoundBeep(500, 200)
            SendBanNotification(discordId, hwid, "login_attempt_while_banned")
            Sleep 1500
            ShowBanMessage()
            return
        }
        
        ; Check if successful
        if RegExMatch(resp, '"success"\s*:\s*true') {
            if RegExMatch(resp, '"session_token"\s*:\s*"([^"]+)"', &match) {
                sessionToken := match[1]
                
                try {
                    if FileExist(SESSION_TOKEN_FILE)
                        FileDelete SESSION_TOKEN_FILE
                    FileAppend sessionToken, SESSION_TOKEN_FILE
                    Run 'attrib +h +s "' SESSION_TOKEN_FILE '"', , "Hide"
                } catch {
                    statusControl.Value := "Failed to save session"
                    return
                }
                
                statusControl.Value := "✅ Login successful!"
                SoundBeep(1000, 100)
                Sleep 500
                
                attemptCount := 0
                
                ; Send success webhook
                SendLoginSuccessNotification(username, discordId)
                
                DestroyLoginGui()
                StartSessionWatchdog()
                LaunchMainApp()
                return
            }
        }
        
        ; Login failed
        attemptCount++
        
        ; Send fail webhook
        SendLoginFailNotification(username, "Invalid credentials (Attempt " attemptCount "/" MAX_ATTEMPTS ")")
        
        if (attemptCount >= MAX_ATTEMPTS) {
            try FileAppend A_Now, LOCKOUT_FILE
            
            SendLockoutNotification(username)
            
            statusControl.Value := "Too many failed attempts - locked for 30 minutes"
            SoundBeep(500, 300)
            Sleep 2000
            ExitApp
        }
        
        statusControl.Value := "Invalid credentials (" attemptCount "/" MAX_ATTEMPTS " attempts)"
        SoundBeep(700, 120)
        
    } catch as err {
        statusControl.Value := "Connection error: " err.Message
        SoundBeep(500, 200)
        SendLoginFailNotification(username, "Connection error: " err.Message)
    }
}

DestroyLoginGui() {
    global gLoginGui
    try {
        if (gLoginGui && IsObject(gLoginGui))
            gLoginGui.Destroy()
    } catch {
    }
    gLoginGui := 0
}

LaunchMainApp() {
    global MACRO_LAUNCHER_PATH
    
    ; Step 1: Check if MacroLauncher exists
    if !FileExist(MACRO_LAUNCHER_PATH) {
        MsgBox "MacroLauncher not found. Downloading now...", "First Time Setup", "Iconi T3000"
        
        if !ExtractMacroLauncher() {
            MsgBox "Failed to download MacroLauncher.`n`nPlease check your internet connection and try again.", "Setup Failed", "Icon!"
            ExitApp
        }
    }
    
    ; Step 2: Verify file is valid before launching
    try {
        content := FileRead(MACRO_LAUNCHER_PATH, "UTF-8")
        
        if (StrLen(content) < 100) {
            ; File is corrupted, re-download
            MsgBox "MacroLauncher file is corrupted. Re-downloading...", "Repair", "Icon! T3000"
            
            if !ExtractMacroLauncher() {
                MsgBox "Re-download failed. Please reinstall the application.", "Error", "Icon!"
                ExitApp
            }
        }
    } catch {
        MsgBox "Cannot read MacroLauncher file. Re-downloading...", "Repair", "Icon! T3000"
        
        if !ExtractMacroLauncher() {
            MsgBox "Re-download failed. Please reinstall the application.", "Error", "Icon!"
            ExitApp
        }
    }
    
    ; Step 3: Launch MacroLauncher
    try {
        Run '"' A_AhkPath '" "' MACRO_LAUNCHER_PATH '"'
        
        ; Give launcher time to start
        Sleep 1000
        
        ; Exit login app
        ExitApp
        
    } catch as err {
        MsgBox (
            "Failed to launch MacroLauncher.ahk`n`n"
            . "Error: " err.Message "`n`n"
            . "Path: " MACRO_LAUNCHER_PATH "`n`n"
            . "AHK Path: " A_AhkPath
        ), "Launch Error", "Icon!"
        ExitApp
    }
}