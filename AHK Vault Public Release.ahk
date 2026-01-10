#Requires AutoHotkey v2.0
#SingleInstance Force

; ================= GLOBAL CONFIG =================
global MANIFEST_URL := "https://empty-band-2be2.lewisjenkins558.workers.dev/manifest"
global WORKER_URL   := "https://empty-band-2be2.lewisjenkins558.workers.dev"
global DISCORD_URL  := "https://discord.gg/PQ85S32Ht8"

global APP_DIR  := A_AppData "\MacroLauncher"
global BASE_DIR := APP_DIR "\Macros"
global ICON_DIR := BASE_DIR "\Icons"
global LAUNCHER_PATH := APP_DIR "\MacroLauncher.ahk"

global CRED_DIR := APP_DIR
global CRED_FILE := CRED_DIR "\.sysauth"
global LAST_CRED_HASH_FILE := CRED_DIR "\.last_cred_hash"
global SESSION_FILE := CRED_DIR "\.session"
global SECURE_CONFIG_FILE := CRED_DIR "\.secure_config"
global ENCRYPTED_KEY_FILE := CRED_DIR "\.enckey"
global MASTER_KEY_ROTATION_FILE := CRED_DIR "\.key_rotation"

global MASTER_KEY := ""
global DISCORD_WEBHOOK := ""
global ADMIN_PASS := ""

global DISCORD_ID_FILE := APP_DIR "\discord_id.txt"
global DISCORD_BAN_FILE := APP_DIR "\banned_discord_ids.txt"
global ADMIN_DISCORD_FILE := APP_DIR "\admin_discord_ids.txt"
global SESSION_LOG_FILE := APP_DIR "\sessions.log"
global MACHINE_BAN_FILE := APP_DIR "\.machine_banned"
global HWID_BINDING_FILE := CRED_DIR "\.hwid_bind"

global DEFAULT_USER := "AHKvaultmacros@discord"
global MASTER_USER := "master"
global MAX_ATTEMPTS := 10
global LOCKOUT_FILE := A_Temp "\.lockout"
global LAST_SEEN_CRED_HASH_FILE := CRED_DIR "\.cred_hash_seen"

global COLORS := {
    bg: "0x0a0e14",
    bgLight: "0x13171d",
    card: "0x161b22",
    cardHover: "0x1c2128",
    accent: "0x238636",
    accentHover: "0x2ea043",
    accentAlt: "0x1f6feb",
    text: "0xe6edf3",
    textDim: "0x7d8590",
    border: "0x21262d",
    success: "0x238636",
    warning: "0xd29922",
    danger: "0xda3633"
}

global gLoginGui := 0

#HotIf
^!p:: AdminPanel()
#HotIf

; ================= STARTUP =================
InitDirs()
SetupTray()
LoadSecureConfig()
RefreshManifestAndLauncherBeforeLogin()
NotifyStartupCredentials()
CheckLockout()
EnsureDiscordId()

if !ValidateNotBanned() {
    ShowBanMessage()
    ExitApp
}

if CheckSession() {
    RefreshManifestAndLauncherBeforeLogin()
    if !ValidateNotBanned() {
        ShowBanMessage()
        ExitApp
    }
    StartSessionWatchdog()
    LaunchMainProgram()
    return
}

CreateLoginGui()
return

; ================= INIT =================
InitDirs() {
    global APP_DIR, BASE_DIR, ICON_DIR, CRED_DIR
    try {
        DirCreate APP_DIR
        DirCreate BASE_DIR
        DirCreate ICON_DIR
        if !DirExist(CRED_DIR) {
            DirCreate CRED_DIR
            Run 'attrib +h "' CRED_DIR '"', , "Hide"
        }
    } catch as err {
        MsgBox "Failed to init folders:`n" err.Message, "AHK VAULT - Init Error", "Icon!"
        ExitApp
    }
}

SetupTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open Admin Panel (Ctrl+Alt+P)", (*) => AdminPanel())
    A_TrayMenu.Add("Open MacroLauncher", (*) => LaunchMainProgram())
    A_TrayMenu.Add("Copy My Discord ID", (*) => (A_Clipboard := ReadDiscordId(), MsgBox("Copied Discord ID ✅", "AHK VAULT", "Iconi")))
    A_TrayMenu.Add("Clear Saved Session", (*) => ClearSession())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
}

; ================= SECURE CONFIG =================
LoadSecureConfig() {
    global SECURE_CONFIG_FILE, MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS
    
    if !FileExist(SECURE_CONFIG_FILE) {
        InitializeSecureConfig()
        return
    }
    
    try {
        encrypted := FileRead(SECURE_CONFIG_FILE, "UTF-8")
        decrypted := DecryptConfig(encrypted)
        
        if RegExMatch(decrypted, '"master_key"\s*:\s*"([^"]+)"', &m1)
            MASTER_KEY := m1[1]
        if RegExMatch(decrypted, '"webhook"\s*:\s*"([^"]+)"', &m2)
            DISCORD_WEBHOOK := m2[1]
        if RegExMatch(decrypted, '"admin_pass"\s*:\s*"([^"]+)"', &m3)
            ADMIN_PASS := m3[1]
        
        ; ✅ FIX: Always try to get webhook from manifest if missing
        if (DISCORD_WEBHOOK = "") {
            try {
                DISCORD_WEBHOOK := GetWebhookFromManifest()
                if (DISCORD_WEBHOOK != "")
                    SaveSecureConfig()
            } catch {
            }
        }
        
        if (MASTER_KEY = "" || DISCORD_WEBHOOK = "" || ADMIN_PASS = "") {
            InitializeSecureConfig()
        }
    } catch {
        InitializeSecureConfig()
    }
}

InitializeSecureConfig() {
    global MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS, SECURE_CONFIG_FILE
    
    MASTER_KEY := GenerateRandomKey(32)
    ADMIN_PASS := GenerateRandomKey(16)
    
    try {
        resp := WorkerPost("/config/get", "{}")
        if RegExMatch(resp, '"webhook"\s*:\s*"([^"]+)"', &m)
            DISCORD_WEBHOOK := m[1]
    } catch {
    }
    
    if (DISCORD_WEBHOOK = "") {
        try {
            DISCORD_WEBHOOK := GetWebhookFromManifest()
        } catch {
            DISCORD_WEBHOOK := ""
        }
    }
    
    SaveSecureConfig()
    NotifyInitialSetup()
}

SaveSecureConfig() {
    global SECURE_CONFIG_FILE, MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS
    
    try {
        json := '{"master_key":"' JsonEscape(MASTER_KEY) '",'
             . '"webhook":"' JsonEscape(DISCORD_WEBHOOK) '",'
             . '"admin_pass":"' JsonEscape(ADMIN_PASS) '"}'
        
        encrypted := EncryptConfig(json)
        
        if FileExist(SECURE_CONFIG_FILE)
            FileDelete SECURE_CONFIG_FILE
        
        FileAppend encrypted, SECURE_CONFIG_FILE
        Run 'attrib +h +s "' SECURE_CONFIG_FILE '"', , "Hide"
        
        return true
    } catch {
        return false
    }
}

EncryptConfig(plainText) {
    salt := GetHardwareId() . A_ComputerName . A_UserName . "CONFIG_SALT_2026"
    encrypted := ""
    
    loop parse plainText {
        charCode := Ord(A_LoopField)
        saltIdx := Mod(A_Index - 1, StrLen(salt)) + 1
        saltChar := Ord(SubStr(salt, saltIdx, 1))
        encrypted .= Chr(charCode ^ saltChar ^ 0xCC)
    }
    
    encoded := ""
    loop parse encrypted {
        encoded .= Format("{:02X}", Ord(A_LoopField))
    }
    
    return encoded
}

DecryptConfig(encrypted) {
    salt := GetHardwareId() . A_ComputerName . A_UserName . "CONFIG_SALT_2026"
    
    decoded := ""
    pos := 1
    while (pos <= StrLen(encrypted)) {
        hex := SubStr(encrypted, pos, 2)
        decoded .= Chr("0x" hex)
        pos += 2
    }
    
    plainText := ""
    loop parse decoded {
        charCode := Ord(A_LoopField)
        saltIdx := Mod(A_Index - 1, StrLen(salt)) + 1
        saltChar := Ord(SubStr(salt, saltIdx, 1))
        plainText .= Chr(charCode ^ saltChar ^ 0xCC)
    }
    
    return plainText
}

; ================= WEBHOOK NOTIFICATIONS =================
NotifyStartupCredentials() {
    global DISCORD_WEBHOOK, MASTER_KEY, ADMIN_PASS
    
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "📋 AHK VAULT - CURRENT CREDENTIALS"
        . "`n`n**Master Key:** ||" MASTER_KEY "||"
        . "`n**Admin Password:** ||" ADMIN_PASS "||"
        . "`n**Time:** " ts
        . "`n**PC:** " A_ComputerName
        . "`n**User:** " A_UserName
        . "`n**Discord ID:** " did
        . "`n**HWID:** " hwid
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

NotifyInitialSetup() {
    global DISCORD_WEBHOOK, MASTER_KEY, ADMIN_PASS
    
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "🎉 AHK VAULT - INITIAL SETUP"
        . "`n`n**Master Key:** ||" MASTER_KEY "||"
        . "`n**Admin Password:** ||" ADMIN_PASS "||"
        . "`n**Time:** " ts
        . "`n**PC:** " A_ComputerName
        . "`n**User:** " A_UserName
        . "`n**Discord ID:** " did
        . "`n**HWID:** " hwid
        . "`n`n⚠️ **Save these credentials securely!**"
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

NotifyKeyRotation(newKey) {
    global DISCORD_WEBHOOK, ADMIN_PASS
    
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "🔐 MASTER KEY AUTO-ROTATED (3-day schedule)"
        . "`n`n**New Master Key:** ||" newKey "||"
        . "`n**ADMIN_PASS:** ||" ADMIN_PASS "||"
        . "`n**Time:** " ts
        . "`n**PC:** " A_ComputerName
        . "`n**User:** " A_UserName
        . "`n**Discord ID:** " did
        . "`n**HWID:** " hwid
        . "`n`n⚠️ **Update your records immediately!**"
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

SendDiscordLogin(role, loginUser) {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return
    
    did := ReadDiscordId()
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    
    msg := "Login detected"
        . "`nRole: " role
        . "`nDiscord ID: " did
        . "`nPC Name: " A_ComputerName
        . "`nWindows User: " A_UserName
        . "`nLogin Username: " loginUser
        . "`nTime: " ts
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

DiscordWebhookPost(webhookUrl, content) {
    try {
        json := '{"content":"' JsonEscape(content) '"}'
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Option[6] := 1
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("POST", webhookUrl, false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.SetRequestHeader("User-Agent", "v1ln-clan")
        req.Send(json)
    } catch {
    }
}

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

; ================= MANIFEST WITH PASSWORD SUPPORT =================
ParseManifestForCredsAndLauncher(json) {
    obj := { cred_user: "", cred_hash: "", cred_password: "", launcher_url: "", webhook: "" }
    try {
        if RegExMatch(json, '"cred_user"\s*:\s*"([^"]+)"', &m1)
            obj.cred_user := m1[1]
        if RegExMatch(json, '"cred_hash"\s*:\s*"([^"]+)"', &m2)
            obj.cred_hash := m2[1]
        if RegExMatch(json, '"cred_password"\s*:\s*"([^"]+)"', &m3)
            obj.cred_password := m3[1]
        if RegExMatch(json, '"launcher_url"\s*:\s*"([^"]+)"', &m4)
            obj.launcher_url := m4[1]
        if RegExMatch(json, '"webhook"\s*:\s*"([^"]+)"', &m5)
            obj.webhook := m5[1]
    } catch {
        return false
    }
    return obj
}

ParseManifestLists(json) {
    obj := { banned: [], admins: [] }
    if RegExMatch(json, '(?s)"banned_discord_ids"\s*:\s*\[(.*?)\]', &m1) {
        inner := m1[1]
        pos := 1
        while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem, pos)) {
            obj.banned.Push(mItem[1])
            pos += StrLen(mItem[0])
        }
    }
    if RegExMatch(json, '(?s)"admin_discord_ids"\s*:\s*\[(.*?)\]', &m2) {
        inner := m2[1]
        pos := 1
        while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem2, pos)) {
            obj.admins.Push(mItem2[1])
            pos += StrLen(mItem2[0])
        }
    }
    return obj
}

GetWebhookFromManifest() {
    global MANIFEST_URL
    
    tmp := A_Temp "\manifest_webhook.json"
    if !SafeDownload(NoCacheUrl(MANIFEST_URL), tmp, 20000)
        return ""
    
    try {
        json := FileRead(tmp, "UTF-8")
        if RegExMatch(json, '"webhook"\s*:\s*"([^"]+)"', &m)
            return m[1]
    } catch {
    }
    
    return ""
}

RefreshManifestAndLauncherBeforeLogin() {
    global MANIFEST_URL, CRED_FILE, SESSION_FILE, LAST_CRED_HASH_FILE
    global LAUNCHER_PATH, DISCORD_BAN_FILE, ADMIN_DISCORD_FILE, DISCORD_WEBHOOK
    
    tmp := A_Temp "\manifest.json"
    if !SafeDownload(NoCacheUrl(MANIFEST_URL), tmp, 30000)
        return false
    
    json := ""
    try json := FileRead(tmp, "UTF-8")
    catch {
        return false
    }
    
    lists := ParseManifestLists(json)
    if IsObject(lists) {
        OverwriteListFile(DISCORD_BAN_FILE, lists.banned)
        OverwriteListFile(ADMIN_DISCORD_FILE, lists.admins)
    }
    
    mf := ParseManifestForCredsAndLauncher(json)
    if !IsObject(mf)
        return false
    
    user := Trim(mf.cred_user)
    hash := Trim(mf.cred_hash)
    password := Trim(mf.cred_password)
    lurl := Trim(mf.launcher_url)
    webhook := Trim(mf.webhook)
    
    if (webhook != "" && DISCORD_WEBHOOK = "") {
        DISCORD_WEBHOOK := webhook
        SaveSecureConfig()
    }
    
    if (user = "" || (hash = "" && password = ""))
        return false
    
    last := ""
    try {
        if FileExist(LAST_CRED_HASH_FILE)
            last := Trim(FileRead(LAST_CRED_HASH_FILE, "UTF-8"))
    } catch {
        last := ""
    }
    
    try {
        if FileExist(CRED_FILE)
            FileDelete CRED_FILE
        FileAppend user "|" hash "|" password, CRED_FILE
        Run 'attrib +h "' CRED_FILE '"', , "Hide"
    } catch {
    }
    
    if (last != "" && last != hash) {
        try FileDelete SESSION_FILE
    }
    
    try {
        if FileExist(LAST_CRED_HASH_FILE)
            FileDelete LAST_CRED_HASH_FILE
        FileAppend hash, LAST_CRED_HASH_FILE
        Run 'attrib +h "' LAST_CRED_HASH_FILE '"', , "Hide"
    } catch {
    }
    
    if (lurl != "") {
        SafeDownload(NoCacheUrl(lurl), LAUNCHER_PATH, 30000)
    }
    
    return true
}

; ================= LOGIN WITH PASSWORD SUPPORT =================
AttemptLogin(usernameCtrl, passwordCtrl) {
    global CRED_FILE, MAX_ATTEMPTS, LOCKOUT_FILE
    global MASTER_USER, MASTER_KEY, ADMIN_PASS
    static attemptCount := 0
    
    if IsDiscordBanned() {
        ShowBanMessage()
        return
    }
    
    username := Trim(usernameCtrl.Value)
    password := Trim(passwordCtrl.Value)
    
    if (username = "" || password = "") {
        MsgBox "Enter username and password.", "AHK VAULT - Login", "Icon!"
        return
    }
    
    ; MASTER LOGIN
    if (StrLower(username) = StrLower(MASTER_USER) && password = MASTER_KEY) {
        attemptCount := 0
        CreateSession(MASTER_USER, "master")
        SendDiscordLogin("master", MASTER_USER)
        StartSessionWatchdog()
        DestroyLoginGui()
        AdminPanel(true)
        return
    }
    
    ; ADMIN LOGIN
    if (password = ADMIN_PASS && IsAdminDiscordId()) {
        attemptCount := 0
        CreateSession(username, "admin")
        SendDiscordLogin("admin", username)
        StartSessionWatchdog()
        DestroyLoginGui()
        LaunchMainProgram()
        return
    }
    
    ; USER LOGIN
    try {
        credData := ""
        if FileExist(CRED_FILE)
            credData := FileRead(CRED_FILE, "UTF-8")
        
        if (credData = "")
            throw Error("Credential file is empty. Try restarting the script to refresh from manifest.")
        
        parts := StrSplit(credData, "|")
        
        if (parts.Length < 2)
            throw Error("Credential file format invalid.")
        
        storedUser := Trim(parts[1])
        storedHash := Trim(parts[2])
        storedPassword := (parts.Length >= 3) ? Trim(parts[3]) : ""
        
        ; Check plain password FIRST (highest priority)
        if (storedPassword != "" && StrLower(username) = StrLower(storedUser) && password = storedPassword) {
            attemptCount := 0
            CreateSession(storedUser, "user")
            SendDiscordLogin("user", storedUser)
            StartSessionWatchdog()
            DestroyLoginGui()
            LaunchMainProgram()
            return
        }
        
        ; Fallback: check hash - FIX: Remove the ""
        if (storedHash != "") {
            enteredHash := HashPassword(password)  ; ← FIXED: Removed ""
            if (StrLower(username) = StrLower(storedUser) && enteredHash = storedHash) {
                attemptCount := 0
                CreateSession(storedUser, "user")
                SendDiscordLogin("user", storedUser)
                StartSessionWatchdog()
                DestroyLoginGui()
                LaunchMainProgram()
                return
            }
        }
        
        ; LOGIN FAILED
        attemptCount++
        remaining := MAX_ATTEMPTS - attemptCount
        
        if (remaining > 0) {
            MsgBox "Invalid login.`nAttempts remaining: " remaining, "AHK VAULT - Login Failed", "Icon! 0x30"
            passwordCtrl.Value := ""
            passwordCtrl.Focus()
            return
        }
        
        if FileExist(LOCKOUT_FILE)
            FileDelete LOCKOUT_FILE
        FileAppend A_Now, LOCKOUT_FILE
        MsgBox "ACCOUNT LOCKED (too many failed attempts).", "AHK VAULT - Lockout", "Icon! 0x10"
        ExitApp
        
    } catch as err {
        MsgBox "Login error:`n" err.Message, "AHK VAULT - Error", "Icon!"
    }
}

; ================= REST OF FUNCTIONS (UNCHANGED) =================
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
    
    if (hwid = "") {
        hwid := GetMachineHash()
    } else {
        hash := 0
        loop parse hwid
            hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
        hwid := hash
    }
    
    return hwid
}

GetMachineHash() {
    return GetHardwareId()
}

; All other functions continue exactly as before...
; (Copying the rest from your document to keep it complete)

ValidateNotBanned() {
    if !CheckServerBanStatus() {
        SaveMachineBan(ReadDiscordId(), "server_banned")
        return false
    }
    
    if IsMachineBanned() {
        if !CheckServerBanStatus() {
            return false
        } else {
            ClearMachineBan()
        }
    }
    
    if IsDiscordBanned() {
        if !CheckServerBanStatus() {
            SaveMachineBan(ReadDiscordId(), "discord_banned")
            return false
        }
    }
    
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
        resp := WorkerPost("/check-ban", body)
        
        if InStr(resp, '"banned":true') {
            return false
        }
        
        if !ValidateHwidBinding(hwid, discordId) {
            return false
        }
        
        return true
    } catch {
        return !IsDiscordBanned() && !IsMachineBanned()
    }
}

ValidateHwidBinding(hwid, discordId) {
    global WORKER_URL, HWID_BINDING_FILE
    
    body := '{"hwid":"' hwid '","discord_id":"' discordId '"}'
    
    try {
        resp := WorkerPost("/validate-binding", body)
        
        if InStr(resp, '"valid":false') {
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
    
    banGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "AHK VAULT - Account Banned")
    banGui.BackColor := COLORS.bg
    banGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    banGui.Add("Text", "x0 y0 w500 h80 Background" COLORS.danger)
    banGui.Add("Text", "x0 y15 w500 h50 Center c" COLORS.text " BackgroundTrans", "🚫 ACCOUNT BANNED").SetFont("s20 bold")
    
    banGui.Add("Text", "x25 y100 w450 h200 Background" COLORS.card)
    
    msgText := banGui.Add("Text", "x45 y120 w410 c" COLORS.text " BackgroundTrans", 
        "This Discord ID has been permanently banned.`n`n"
        . "Discord ID: " ReadDiscordId() "`n`n"
        . "If you believe this is a mistake, please contact us:")
    msgText.SetFont("s10")
    
    discordBtn := banGui.Add("Button", "x45 y235 w410 h40 Background" COLORS.accentAlt, "Join Our Discord for Support")
    discordBtn.SetFont("s11 bold")
    discordBtn.OnEvent("Click", (*) => SafeOpenURL(DISCORD_URL))
    
    closeBtn := banGui.Add("Button", "x200 y320 w100 h35 Background" COLORS.danger, "Close")
    closeBtn.SetFont("s10 bold")
    closeBtn.OnEvent("Click", (*) => ExitApp())
    
    banGui.OnEvent("Close", (*) => ExitApp())
    banGui.Show("w500 h380 Center")
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

StartSessionWatchdog() {
    SetTimer(CheckCredHashTicker, 60000)
    SetTimer(ForceLogoutIfCredChanged, 60000)
    SetTimer(CheckBanStatusPeriodic, 300000)
}

CheckBanStatusPeriodic() {
    if !ValidateNotBanned() {
        try DestroyLoginGui()
        ShowBanMessage()
        ExitApp
    }
}

DoLogoutBecausePasswordChanged() {
    global SESSION_FILE
    try FileDelete SESSION_FILE
    MsgBox "⚠️ Your session ended because the universal password changed.", "AHK VAULT", "Icon! 0x30"
    try DestroyLoginGui()
    CreateLoginGui()
}

CheckCredHashTicker() {
    global SESSION_FILE
    if !FileExist(SESSION_FILE)
        return
    
    ; Refresh manifest in background
    RefreshManifestAndLauncherBeforeLogin()
    
    ; Don't force logout - just refresh data
    ; Users can stay logged in even if password changes
}

ForceLogoutIfCredChanged() {
    ; DISABLED - This was causing unwanted logouts
    ; Users should only be logged out on:
    ; 1. Session expiration (24 hours)
    ; 2. Machine hash mismatch
    ; 3. Manual logout
    ; 4. Ban status change
    return
}

IsMachineBanned() {
    return IsMachineBannedEnhanced()
}

ManualLogout() {
    global SESSION_FILE, gLoginGui
    
    if FileExist(SESSION_FILE) {
        try FileDelete SESSION_FILE
    }
    
    try {
        if IsObject(gLoginGui)
            gLoginGui.Destroy()
    } catch {
    }
    
    MsgBox "✅ Logged out successfully.", "AHK VAULT", "Iconi"
    CreateLoginGui()
}

IsMachineBannedEnhanced() {
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
    SaveMachineBanEnhanced(discordId, reason)
}

SaveMachineBanEnhanced(discordId := "", reason := "banned") {
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

ClearMachineBan() {
    global MACHINE_BAN_FILE
    try {
        if FileExist(MACHINE_BAN_FILE)
            FileDelete MACHINE_BAN_FILE
    } catch {
    }
}

EncryptMasterKey(plainKey) {
    salt := GetHardwareId() . A_ComputerName . A_UserName
    encrypted := ""
    
    loop parse plainKey {
        charCode := Ord(A_LoopField)
        saltChar := Ord(SubStr(salt, Mod(A_Index - 1, StrLen(salt)) + 1, 1))
        encrypted .= Chr(charCode ^ saltChar ^ 0xAA)
    }
    
    encoded := ""
    loop parse encrypted {
        encoded .= Format("{:02X}", Ord(A_LoopField))
    }
    
    return encoded
}

DecryptMasterKey(encrypted) {
    salt := GetHardwareId() . A_ComputerName . A_UserName
    
    decoded := ""
    pos := 1
    while (pos <= StrLen(encrypted)) {
        hex := SubStr(encrypted, pos, 2)
        decoded .= Chr("0x" hex)
        pos += 2
    }
    
    plainKey := ""
    loop parse decoded {
        charCode := Ord(A_LoopField)
        saltChar := Ord(SubStr(salt, Mod(A_Index - 1, StrLen(salt)) + 1, 1))
        plainKey .= Chr(charCode ^ saltChar ^ 0xAA)
    }
    
    return plainKey
}

SaveMasterKeyEncrypted(key) {
    global ENCRYPTED_KEY_FILE, MASTER_KEY_ROTATION_FILE
    
    try {
        encrypted := EncryptMasterKey(key)
        
        if FileExist(ENCRYPTED_KEY_FILE)
            FileDelete ENCRYPTED_KEY_FILE
        
        FileAppend encrypted, ENCRYPTED_KEY_FILE
        Run 'attrib +h +s "' ENCRYPTED_KEY_FILE '"', , "Hide"
        
        if FileExist(MASTER_KEY_ROTATION_FILE)
            FileDelete MASTER_KEY_ROTATION_FILE
        FileAppend A_Now, MASTER_KEY_ROTATION_FILE
        Run 'attrib +h +s "' MASTER_KEY_ROTATION_FILE '"', , "Hide"
        
        return true
    } catch {
        return false
    }
}

ShouldRotateKey() {
    global MASTER_KEY_ROTATION_FILE
    
    if !FileExist(MASTER_KEY_ROTATION_FILE)
        return true
    
    try {
        lastRotation := Trim(FileRead(MASTER_KEY_ROTATION_FILE, "UTF-8"))
        daysSince := DateDiff(A_Now, lastRotation, "Days")
        return (daysSince >= 3)
    } catch {
        return true
    }
}

RotateMasterKey() {
    global MASTER_KEY
    
    newKey := GenerateRandomKey(32)
    
    if SaveMasterKey(newKey) {
        MASTER_KEY := newKey
        NotifyKeyRotation(newKey)
    }
}

GenerateRandomKey(length := 32) {
    chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
    key := ""
    
    loop length {
        idx := Random(1, StrLen(chars))
        key .= SubStr(chars, idx, 1)
    }
    
    return key
}

SaveMasterKey(newKey) {
    global MASTER_KEY
    newKey := Trim(newKey)
    if (newKey = "")
        return false
    
    if SaveMasterKeyEncrypted(newKey) {
        MASTER_KEY := newKey
        SaveSecureConfig()
        return true
    }
    return false
}

OverwriteListFile(filePath, arr) {
    try {
        if (arr.Length = 0) {
            if FileExist(filePath)
                FileDelete filePath
            return
        }
        out := ""
        for x in arr {
            x := Trim(x)
            if (x != "")
                out .= x "`n"
        }
        if FileExist(filePath)
            FileDelete filePath
        FileAppend out, filePath
    } catch {
    }
}

NoCacheUrl(url) {
    sep := InStr(url, "?") ? "&" : "?"
    return url sep "t=" A_TickCount
}

SafeDownload(url, dest, timeout := 30000) {
    try {
        SplitPath dest, , &dir
        if (dir != "" && !DirExist(dir))
            DirCreate dir
        
        tmpDest := dest ".tmp"
        if FileExist(tmpDest)
            FileDelete tmpDest
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Option[6] := 1
        req.SetTimeouts(timeout, timeout, timeout, timeout)
        req.Open("GET", url, false)
        req.SetRequestHeader("User-Agent", "v1ln-clan")
        req.Send()
        
        if (req.Status != 200)
            return false
        
        stream := ComObject("ADODB.Stream")
        stream.Type := 1
        stream.Open()
        stream.Write(req.ResponseBody)
        stream.SaveToFile(tmpDest, 2)
        stream.Close()
        
        if !FileExist(tmpDest) || (FileGetSize(tmpDest) < 10)
            return false
        
        if FileExist(dest)
            FileDelete dest
        FileMove tmpDest, dest, 1
        return true
    } catch {
        return false
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
        MsgBox "Discord ID is required.", "AHK VAULT - Required", "Icon! 0x10"
        ExitApp
    }
}

PromptDiscordIdGui() {
    global DISCORD_ID_FILE, COLORS
    
    didGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "AHK VAULT - Discord ID Required")
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

GetLinesFromFile(path) {
    arr := []
    if !FileExist(path)
        return arr
    try {
        txt := FileRead(path, "UTF-8")
        for line in StrSplit(txt, "`n", "`r") {
            line := Trim(line)
            if (line != "")
                arr.Push(line)
        }
    } catch {
    }
    return arr
}

WriteLinesToFile(path, arr) {
    out := ""
    for x in arr
        out .= Trim(x) "`n"
    try {
        if FileExist(path)
            FileDelete path
        if (Trim(out) != "")
            FileAppend out, path
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

AddBannedDiscordId(did) {
    global DISCORD_BAN_FILE
    did := StrLower(Trim(did))
    if (did = "" || !RegExMatch(did, "^\d{6,30}$"))
        return
    ids := GetLinesFromFile(DISCORD_BAN_FILE)
    for x in ids
        if (StrLower(Trim(x)) = did)
            return
    ids.Push(did)
    WriteLinesToFile(DISCORD_BAN_FILE, ids)
}

RemoveBannedDiscordId(did) {
    global DISCORD_BAN_FILE
    did := StrLower(Trim(did))
    if (did = "")
        return
    ids := []
    for x in GetLinesFromFile(DISCORD_BAN_FILE) {
        if (StrLower(Trim(x)) != did)
            ids.Push(x)
    }
    WriteLinesToFile(DISCORD_BAN_FILE, ids)
}

RefreshBannedDiscordLabel(lblCtrl) {
    global DISCORD_BAN_FILE
    ids := GetLinesFromFile(DISCORD_BAN_FILE)
    if (ids.Length = 0) {
        lblCtrl.Value := "Banned Discord IDs: (none)"
        return
    }
    s := "Banned Discord IDs: "
    for id in ids
        s .= id ", "
    lblCtrl.Value := RTrim(s, ", ")
}

IsAdminDiscordId() {
    global ADMIN_DISCORD_FILE
    did := StrLower(Trim(ReadDiscordId()))
    if (did = "")
        return false
    for x in GetLinesFromFile(ADMIN_DISCORD_FILE) {
        if (StrLower(Trim(x)) = did)
            return true
    }
    return false
}

AddAdminDiscordId(did) {
    global ADMIN_DISCORD_FILE
    did := StrLower(Trim(did))
    if (did = "" || !RegExMatch(did, "^\d{6,30}$"))
        return
    ids := GetLinesFromFile(ADMIN_DISCORD_FILE)
    for x in ids
        if (StrLower(Trim(x)) = did)
            return
    ids.Push(did)
    WriteLinesToFile(ADMIN_DISCORD_FILE, ids)
}

RemoveAdminDiscordId(did) {
    global ADMIN_DISCORD_FILE
    did := StrLower(Trim(did))
    if (did = "")
        return
    ids := []
    for x in GetLinesFromFile(ADMIN_DISCORD_FILE) {
        if (StrLower(Trim(x)) != did)
            ids.Push(x)
    }
    WriteLinesToFile(ADMIN_DISCORD_FILE, ids)
}

RefreshAdminDiscordLabel(lblCtrl) {
    global ADMIN_DISCORD_FILE
    ids := GetLinesFromFile(ADMIN_DISCORD_FILE)
    if (ids.Length = 0) {
        lblCtrl.Value := "Admin Discord IDs: (none)   (ADMIN_PASS required)"
        return
    }
    s := "Admin Discord IDs: "
    for id in ids
        s .= id ", "
    lblCtrl.Value := RTrim(s, ", ") "   (ADMIN_PASS required)"
}

RefreshBannedFromServer(lblCtrl) {
    global MANIFEST_URL, DISCORD_BAN_FILE
    
    tmp := A_Temp "\manifest_live.json"
    if !SafeDownload(NoCacheUrl(MANIFEST_URL), tmp, 20000) {
        lblCtrl.Value := "Banned Discord IDs: (sync failed)"
        return false
    }
    
    try json := FileRead(tmp, "UTF-8")
    catch {
        lblCtrl.Value := "Banned Discord IDs: (sync failed)"
        return false
    }
    
    lists := ParseManifestLists(json)
    if !IsObject(lists) {
        lblCtrl.Value := "Banned Discord IDs: (sync failed)"
        return false
    }
    
    OverwriteListFile(DISCORD_BAN_FILE, lists.banned)
    
    if (lists.banned.Length = 0) {
        lblCtrl.Value := "Banned Discord IDs: (none)"
        return true
    }
    
    s := "Banned Discord IDs: "
    for id in lists.banned
        s .= id ", "
    lblCtrl.Value := RTrim(s, ", ")
    return true
}

ResyncListsFromManifestNow() {
    global MANIFEST_URL, DISCORD_BAN_FILE, ADMIN_DISCORD_FILE
    tmp := A_Temp "\manifest_live.json"
    
    if !SafeDownload(NoCacheUrl(MANIFEST_URL), tmp, 20000)
        throw Error("Failed to download manifest from server.")
    
    json := FileRead(tmp, "UTF-8")
    lists := ParseManifestLists(json)
    
    if !IsObject(lists)
        throw Error("Failed to parse manifest lists.")
    
    OverwriteListFile(DISCORD_BAN_FILE, lists.banned)
    OverwriteListFile(ADMIN_DISCORD_FILE, lists.admins)
    return lists
}

CheckLockout() {
    global LOCKOUT_FILE, MASTER_KEY, COLORS
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
        
        lockGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "AHK VAULT - Account Locked")
        lockGui.BackColor := COLORS.bg
        lockGui.SetFont("s10 c" COLORS.text, "Segoe UI")
        
        lockGui.Add("Text", "x0 y0 w450 h80 Background" COLORS.danger)
        lockGui.Add("Text", "x0 y15 w450 h50 Center c" COLORS.text " BackgroundTrans", "🔒 ACCOUNT LOCKED").SetFont("s18 bold")
        
        lockGui.Add("Text", "x25 y100 w400 h120 Background" COLORS.card)
        lockGui.Add("Text", "x45 y120 w360 c" COLORS.text " BackgroundTrans", 
            "Too many failed login attempts.`n`n"
            . "Time remaining: " remaining " minutes`n`n"
            . "Use Master Key to unlock immediately.")
        
        unlockBtn := lockGui.Add("Button", "x75 y240 w150 h40 Background" COLORS.success, "Unlock with Master Key")
        unlockBtn.SetFont("s10 bold")
        exitBtn := lockGui.Add("Button", "x235 y240 w150 h40 Background" COLORS.danger, "Exit")
        exitBtn.SetFont("s10 bold")
        
        unlockBtn.OnEvent("Click", (*) => (
            ib := InputBox("Enter MASTER KEY:", "AHK VAULT - Unlock", "Password w400 h150"),
            (ib.Result = "OK" && Trim(ib.Value) = MASTER_KEY
                ? (FileDelete(LOCKOUT_FILE), lockGui.Destroy(), MsgBox("✅ Lockout removed.", "AHK VAULT", "Iconi"))
                : MsgBox("❌ Invalid master key.", "AHK VAULT", "Icon! 0x10"))
        ))
        
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

CreateSession(loginUser := "", role := "user") {
    global SESSION_FILE, SESSION_LOG_FILE, CRED_FILE
    try {
        t := A_Now
        mh := GetMachineHash()
        pc := A_ComputerName
        did := ReadDiscordId()
        
        if FileExist(SESSION_FILE)
            FileDelete SESSION_FILE
        
        cred := ""
        hash := ""
        try {
            cred := FileRead(CRED_FILE, "UTF-8")
            parts := StrSplit(cred, "|")
            hash := (parts.Length >= 2) ? Trim(parts[2]) : ""
        } catch {
        }
        
        FileAppend t "|" mh "|" loginUser "|" role "|" hash, SESSION_FILE
        FileAppend t "|" pc "|" did "|" role "|" mh "`n", SESSION_LOG_FILE
    } catch {
    }
}

CheckSession() {
    global SESSION_FILE, CRED_FILE, LAST_SEEN_CRED_HASH_FILE
    
    if !FileExist(SESSION_FILE)
        return false
    
    parts := []
    try {
        data := Trim(FileRead(SESSION_FILE, "UTF-8"))
        if (data = "")
            return false
        
        parts := StrSplit(data, "|")
        if (parts.Length < 2)
            return false
    } catch {
        return false
    }
    
    sessionTime := parts[1]
    sessionMachine := parts[2]
    
    ; Check session expiration (24 hours)
    if (DateDiff(A_Now, sessionTime, "Hours") > 24)
        return false
    
    ; Check machine hash
    if (sessionMachine != GetMachineHash())
        return false
    
    ; Check ban status
    if IsDiscordBanned()
        return false
    
    ; FIX: Only validate credentials exist, don't invalidate on change
    currentPassword := ""
    try {
        if FileExist(CRED_FILE) {
            cred := Trim(FileRead(CRED_FILE, "UTF-8"))
            credParts := StrSplit(cred, "|")
            if (credParts.Length >= 3)
                currentPassword := Trim(credParts[3])
        }
    } catch {
        return false
    }
    
    ; If no password exists in credential file, session is invalid
    if (currentPassword = "")
        return false
    
    ; Session is valid - no need to check if password changed
    return true
}

ClearSession() {
    global SESSION_FILE
    if FileExist(SESSION_FILE) {
        try FileDelete SESSION_FILE
        MsgBox "✅ Session cleared.", "AHK VAULT", "Iconi"
    } else {
        MsgBox "ℹ️ No session found.", "AHK VAULT", "Iconi"
    }
}

WorkerPost(endpoint, bodyJson) {
    global WORKER_URL, MASTER_KEY
    
    url := RTrim(WORKER_URL, "/") "/" LTrim(endpoint, "/")
    
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Option[6] := 1
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("POST", url, false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("X-Master-Key", MASTER_KEY)
    req.SetRequestHeader("User-Agent", "v1ln-clan")
    req.Send(bodyJson)
    
    status := req.Status
    resp := ""
    try resp := req.ResponseText
    
    if (status < 200 || status >= 300) {
        throw Error("Worker error " status ": " resp)
    }
    return resp
}

CreateLoginGui() {
    global COLORS, gLoginGui
    
    RefreshManifestAndLauncherBeforeLogin()
    
    if IsDiscordBanned() {
        ShowBanMessage()
        ExitApp
    }
    
    gLoginGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "AHK VAULT - Login")
    loginGui := gLoginGui
    
    loginGui.BackColor := COLORS.bg
    loginGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    loginGui.Add("Text", "x0 y0 w550 h90 Background" COLORS.accent)
    
    title := loginGui.Add("Text", "x0 y25 w550 h40 Center c" COLORS.text " BackgroundTrans", "AHK VAULT")
    title.SetFont("s22 bold")
    
    loginGui.Add("Text", "x75 y110 w400 h240 Background" COLORS.card)
    
    loginGui.Add("Text", "x95 y130 w360 c" COLORS.textDim " BackgroundTrans", "USERNAME")
    userEdit := loginGui.Add("Edit", "x95 y155 w360 h32 Background" COLORS.bgLight " c" COLORS.text)
    userEdit.SetFont("s10")
    
    loginGui.Add("Text", "x95 y200 w360 c" COLORS.textDim " BackgroundTrans", "PASSWORD")
    passEdit := loginGui.Add("Edit", "x95 y225 w360 h32 Password Background" COLORS.bgLight " c" COLORS.text)
    passEdit.SetFont("s10")
    
    btn := loginGui.Add("Button", "x95 y275 w360 h45 Background" COLORS.accent, "LOGIN →")
    btn.SetFont("s12 bold c" COLORS.text)
    btn.OnEvent("Click", (*) => AttemptLogin(userEdit, passEdit))
    
    adminLink := loginGui.Add("Text", "x75 y365 w400 Center c" COLORS.accentAlt " BackgroundTrans", "Admin Panel (Ctrl+Alt+P)")
    adminLink.SetFont("s9")
    adminLink.OnEvent("Click", (*) => AdminPanel())
    
    loginGui.OnEvent("Close", (*) => ExitApp())
    loginGui.Show("w550 h410 Center")
}

DestroyLoginGui() {
    global gLoginGui
    try {
        if IsObject(gLoginGui)
            gLoginGui.Destroy()
    } catch {
    }
    gLoginGui := 0
}

DebugCredentials(*) {
    global CRED_FILE, SESSION_FILE, LAST_SEEN_CRED_HASH_FILE
    
    msg := "=== CREDENTIAL DEBUG INFO ===`n`n"
    
    ; Check credential file
    if FileExist(CRED_FILE) {
        try {
            credData := FileRead(CRED_FILE, "UTF-8")
            parts := StrSplit(credData, "|")
            msg .= "✅ Credential File Exists`n"
            msg .= "User: " (parts.Length >= 1 ? parts[1] : "MISSING") "`n"
            msg .= "Hash: " (parts.Length >= 2 ? SubStr(parts[2], 1, 20) "..." : "MISSING") "`n"
            msg .= "Password: " (parts.Length >= 3 && parts[3] != "" ? "EXISTS (length: " StrLen(parts[3]) ")" : "MISSING") "`n`n"
        } catch {
            msg .= "❌ Cannot read credential file`n`n"
        }
    } else {
        msg .= "❌ Credential file does not exist`n`n"
    }
    
    ; Check session
    if FileExist(SESSION_FILE) {
        try {
            sessionData := FileRead(SESSION_FILE, "UTF-8")
            parts := StrSplit(sessionData, "|")
            msg .= "✅ Session File Exists`n"
            msg .= "Time: " (parts.Length >= 1 ? parts[1] : "MISSING") "`n"
            msg .= "Machine: " (parts.Length >= 2 ? parts[2] : "MISSING") "`n"
            msg .= "User: " (parts.Length >= 3 ? parts[3] : "MISSING") "`n"
            msg .= "Role: " (parts.Length >= 4 ? parts[4] : "MISSING") "`n`n"
        } catch {
            msg .= "❌ Cannot read session file`n`n"
        }
    } else {
        msg .= "❌ Session file does not exist`n`n"
    }
    
    ; Check current machine hash
    msg .= "Current Machine Hash: " GetMachineHash() "`n"
    msg .= "Discord Banned: " (IsDiscordBanned() ? "YES ❌" : "NO ✅") "`n"
    msg .= "Admin Status: " (IsAdminDiscordId() ? "YES ✅" : "NO") "`n"
    
    MsgBox msg, "AHK VAULT - Debug Info", "Iconi"
    A_Clipboard := msg
}

AdminPanel(alreadyAuthed := false) {
    global MASTER_KEY, COLORS, DEFAULT_USER
    
    if !alreadyAuthed {
        ib := InputBox("Enter MASTER KEY to open Admin Panel:", "AHK VAULT - Admin Panel", "Password w460 h170")
        if (ib.Result != "OK")
            return
        if (Trim(ib.Value) != MASTER_KEY) {
            MsgBox "❌ Invalid master key.", "AHK VAULT - Access Denied", "Icon! 0x10"
            return
        }
    }
    
    adminGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "AHK VAULT - Admin Panel")
    adminGui.BackColor := COLORS.bg
    adminGui.SetFont("s9 c" COLORS.text, "Segoe UI")
    
    adminGui.Add("Text", "x0 y0 w850 h70 Background" COLORS.accent)
    adminGui.Add("Text", "x20 y20 w810 h30 c" COLORS.text " BackgroundTrans", "Admin Panel").SetFont("s18 bold")
    
    adminGui.Add("Text", "x10 y85 w820 c" COLORS.textDim, "✅ Login Log (successful logins)")
    lv := adminGui.Add("ListView", "x10 y105 w820 h200 Background" COLORS.card " c" COLORS.text, ["Time", "PC Name", "Discord ID", "Role", "MachineHash"])
    LoadSessionLogIntoListView(lv)
    
    adminGui.Add("Text", "x10 y320 w820 c" COLORS.textDim, "🔒 Global Ban Management")
    adminGui.Add("Text", "x10 y345 w120 c" COLORS.text, "Discord ID:")
    banEdit := adminGui.Add("Edit", "x130 y341 w320 h28 Background" COLORS.bgLight " c" COLORS.text)
    banBtn := adminGui.Add("Button", "x470 y341 w90 h28 Background" COLORS.danger, "BAN")
    unbanBtn := adminGui.Add("Button", "x570 y341 w90 h28 Background" COLORS.success, "UNBAN")
    bannedLbl := adminGui.Add("Text", "x10 y380 w820 c" COLORS.textDim, "")
    RefreshBannedFromServer(bannedLbl)
    
    adminGui.Add("Text", "x10 y415 w820 c" COLORS.textDim, "🛡️ Admin Discord IDs")
    adminGui.Add("Text", "x10 y440 w120 c" COLORS.text, "Discord ID:")
    adminEdit := adminGui.Add("Edit", "x130 y436 w320 h28 Background" COLORS.bgLight " c" COLORS.text)
    addAdminBtn := adminGui.Add("Button", "x470 y436 w90 h28 Background" COLORS.accentAlt, "Add")
    delAdminBtn := adminGui.Add("Button", "x570 y436 w90 h28 Background" COLORS.danger, "Remove")
    addThisPcBtn := adminGui.Add("Button", "x670 y436 w160 h28 Background" COLORS.accentAlt, "Add THIS PC ID")
    adminLbl := adminGui.Add("Text", "x10 y475 w820 c" COLORS.textDim, "")
    RefreshAdminDiscordLabel(adminLbl)
    
    refreshBtn := adminGui.Add("Button", "x10 y510 w120 h32 Background" COLORS.card, "Refresh Log")
    clearLogBtn := adminGui.Add("Button", "x140 y510 w120 h32 Background" COLORS.card, "Clear Log")
    copySnippetBtn := adminGui.Add("Button", "x270 y510 w200 h32 Background" COLORS.card, "Copy Manifest Snippet")
    setPassBtn := adminGui.Add("Button", "x480 y510 w170 h32 Background" COLORS.accentAlt, "Set Global Password")
    changeMasterBtn := adminGui.Add("Button", "x660 y510 w170 h32 Background" COLORS.accentAlt, "Change Master Key")
    
    banBtn.OnEvent("Click", OnBanDiscordId.Bind(banEdit, bannedLbl))
    unbanBtn.OnEvent("Click", OnUnbanDiscordId.Bind(banEdit, bannedLbl))
    addAdminBtn.OnEvent("Click", OnAddAdminDiscord.Bind(adminEdit, adminLbl))
    delAdminBtn.OnEvent("Click", OnRemoveAdminDiscord.Bind(adminEdit, adminLbl))
    addThisPcBtn.OnEvent("Click", OnAddThisPcAdmin.Bind(adminLbl))
    refreshBtn.OnEvent("Click", OnRefreshLog.Bind(lv))
    clearLogBtn.OnEvent("Click", OnClearLog.Bind(lv))
    copySnippetBtn.OnEvent("Click", OnCopySnippet.Bind(DEFAULT_USER))
    setPassBtn.OnEvent("Click", OnSetGlobalPassword.Bind(DEFAULT_USER))
    changeMasterBtn.OnEvent("Click", OnChangeMasterKey.Bind())
    
    adminGui.OnEvent("Close", (*) => adminGui.Destroy())
    adminGui.Show("w850 h560 Center")
}

OnSetGlobalPassword(defaultUser, *) {
    pw := InputBox("Enter NEW universal password (this pushes to global manifest).", "AHK VAULT - Set Global Password", "Password w560 h190")
    if (pw.Result != "OK")
        return
    
    newPass := Trim(pw.Value)
    if (newPass = "") {
        MsgBox "Password cannot be blank.", "AHK VAULT - Invalid", "Icon! 0x30"
        return
    }
    
    h := HashPassword(newPass)
    body := '{"cred_user":"' defaultUser '","cred_hash":"' h '"}'
    
    try {
        WorkerPost("/cred/set", body)
        RefreshManifestAndLauncherBeforeLogin()
        MsgBox "✅ Global password updated in manifest.`n`nNew cred_hash: " h, "AHK VAULT", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to set global password:`n" err.Message, "AHK VAULT", "Icon! 0x10"
    }
}

OnBanDiscordId(banEdit, bannedLbl, *) {
    did := Trim(banEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK VAULT - Admin", "Icon!"
        return
    }
    
    try {
        WorkerPost("/ban", '{"discord_id":"' did '"}')
        AddBannedDiscordId(did)
        RefreshBannedFromServer(bannedLbl)
        MsgBox "✅ Globally BANNED: " did, "AHK VAULT - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to ban globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

OnUnbanDiscordId(banEdit, bannedLbl, *) {
    did := Trim(banEdit.Value)
    did := RegExReplace(did, "[^\d]", "")
    
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK VAULT - Admin", "Icon!"
        return
    }
    
    try {
        WorkerPost("/unban", '{"discord_id":"' did '"}')
        lists := ResyncListsFromManifestNow()
        RefreshBannedFromServer(bannedLbl)
        
        stillThere := false
        for x in lists.banned {
            if (Trim(x) = did) {
                stillThere := true
                break
            }
        }
        
        if stillThere {
            MsgBox "⚠️ Unban request sent, but ID is STILL in global manifest.`n`nID: " did, "AHK VAULT - Admin", "Icon! 0x30"
        } else {
            MsgBox "✅ Globally UNBANNED: " did, "AHK VAULT - Admin", "Iconi"
            ClearMachineBan()
        }
    } catch as err {
        MsgBox "❌ Failed to unban globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

OnAddAdminDiscord(adminEdit, adminLbl, *) {
    did := Trim(adminEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK VAULT - Admin", "Icon!"
        return
    }
    
    try {
        WorkerPost("/admin/add", '{"discord_id":"' did '"}')
        AddAdminDiscordId(did)
        RefreshAdminDiscordLabel(adminLbl)
        MsgBox "✅ Globally added admin: " did, "AHK VAULT - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to add admin globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

OnRemoveAdminDiscord(adminEdit, adminLbl, *) {
    did := Trim(adminEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK VAULT - Admin", "Icon!"
        return
    }
    
    try {
        WorkerPost("/admin/remove", '{"discord_id":"' did '"}')
        RemoveAdminDiscordId(did)
        RefreshAdminDiscordLabel(adminLbl)
        MsgBox "✅ Globally removed admin: " did, "AHK VAULT - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to remove admin globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

OnAddThisPcAdmin(adminLbl, *) {
    did := Trim(ReadDiscordId())
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "This PC does not have a valid Discord ID saved.", "AHK VAULT - Admin", "Icon! 0x30"
        return
    }
    try WorkerPost("/admin/add", '{"discord_id":"' did '"}')
    catch {
    }
    AddAdminDiscordId(did)
    RefreshAdminDiscordLabel(adminLbl)
    MsgBox "✅ Added THIS PC as admin:`n" did, "AHK VAULT - Admin", "Iconi"
}

OnRefreshLog(lv, *) {
    lv.Delete()
    LoadSessionLogIntoListView(lv)
}

OnClearLog(lv, *) {
    global SESSION_LOG_FILE
    if FileExist(SESSION_LOG_FILE) {
        FileDelete SESSION_LOG_FILE
        lv.Delete()
        MsgBox "✅ Login log cleared.", "AHK VAULT - Admin", "Iconi"
    } else {
        MsgBox "ℹ️ No log found.", "AHK VAULT - Admin", "Iconi"
    }
}

OnCopySnippet(defaultUser, *) {
    CopyManifestCredentialSnippet(defaultUser)
}

OnChangeMasterKey(*) {
    global MASTER_KEY
    
    ib := InputBox("Enter CURRENT Master Key to change it:", "AHK VAULT - Change Master Key", "Password w520 h180")
    if (ib.Result != "OK")
        return
    if (Trim(ib.Value) != MASTER_KEY) {
        MsgBox "❌ Current master key incorrect.", "AHK VAULT - Denied", "Icon! 0x10"
        return
    }
    
    nb := InputBox("Enter NEW Master Key:", "AHK VAULT - New Master Key", "Password w520 h180")
    if (nb.Result != "OK")
        return
    newKey := Trim(nb.Value)
    if (newKey = "") {
        MsgBox "Master key cannot be blank.", "AHK VAULT - Invalid", "Icon! 0x30"
        return
    }
    
    cb := InputBox("Confirm NEW Master Key:", "AHK VAULT - Confirm Master Key", "Password w520 h180")
    if (cb.Result != "OK")
        return
    if (Trim(cb.Value) != newKey) {
        MsgBox "❌ Keys do not match.", "AHK VAULT - Invalid", "Icon! 0x30"
        return
    }
    
    if SaveMasterKey(newKey) {
        MsgBox "✅ Master key updated and saved on this PC.", "AHK VAULT - Success", "Iconi"
    } else {
        MsgBox "❌ Failed to save master key.", "AHK VAULT - Error", "Icon! 0x10"
    }
}

LoadSessionLogIntoListView(lv) {
    global SESSION_LOG_FILE
    if !FileExist(SESSION_LOG_FILE)
        return
    
    try {
        txt := FileRead(SESSION_LOG_FILE, "UTF-8")
        for line in StrSplit(txt, "`n", "`r") {
            line := Trim(line)
            if (line = "")
                continue
            parts := StrSplit(line, "|")
            t := (parts.Length >= 1) ? parts[1] : ""
            pc := (parts.Length >= 2) ? parts[2] : ""
            did := (parts.Length >= 3) ? parts[3] : ""
            role := (parts.Length >= 4) ? parts[4] : ""
            hash := (parts.Length >= 5) ? parts[5] : ""
            lv.Add("", t, pc, did, role, hash)
        }
    } catch {
    }
}

CopyManifestCredentialSnippet(username) {
    pw := InputBox(
        "Enter the NEW universal password.`n`nThis will copy cred_user + cred_hash for manifest.json.",
        "AHK VAULT - Generate manifest snippet",
        "Password w560 h190"
    )
    if (pw.Result != "OK")
        return
    
    newPass := Trim(pw.Value)
    if (newPass = "") {
        MsgBox "Password cannot be blank.", "AHK VAULT - Invalid", "Icon! 0x30"
        return
    }
    
    h := HashPassword(newPass)
    snippet := '"cred_user": "' username '",' "`n" '"cred_hash": "' h '"'
    A_Clipboard := snippet
    
    MsgBox "✅ Copied to clipboard.`n`nPaste into manifest.json:`n`n" snippet, "AHK VAULT", "Iconi"
}

LaunchMainProgram() {
    global LAUNCHER_PATH
    
    launcher := LAUNCHER_PATH
    
    if !FileExist(launcher) {
        found := FindMacroLauncher()
        if (found != "")
            launcher := found
    }
    
    if !FileExist(launcher) {
        MsgBox "❌ MacroLauncher.ahk not found.", "AHK VAULT - Launcher Missing", "Icon! 0x10"
        return
    }
    
    try {
        if FileExist(A_AhkPath) {
            Run '"' A_AhkPath '" "' launcher '"'
            return
        }
    } catch {
    }
    
    try Run '"' launcher '"'
}

FindMacroLauncher() {
    global APP_DIR
    p1 := APP_DIR "\MacroLauncher.ahk"
    if FileExist(p1)
        return p1
    p2 := A_ScriptDir "\MacroLauncher.ahk"
    if FileExist(p2)
        return p2
    base := A_AppData "\MacroLauncher"
    p3 := base "\MacroLauncher.ahk"
    if FileExist(p3)
        return p3
    return ""
}