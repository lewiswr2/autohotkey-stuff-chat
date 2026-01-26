#Requires AutoHotkey v2.0
#SingleInstance Force

; ========== ADMIN TOOL - DO NOT DISTRIBUTE TO USERS ==========
; Enhanced Version with Analytics, Profiles, and Categories
; This file should ONLY be on your personal machine

global WORKER_URL := "https://empty-band-2be2.lewisjenkins558.workers.dev"
global WEBHOOK_URL := "https://discord.com/api/webhooks/1459209245294592070/EGWiUXTNSgUY1RrGwwCCLyM22S8Xln1PwPoj10wdqCY1YsPQCT38cLBGgkZcSccYX8r_"
global MASTER_KEY := "A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7"
global CURRENT_VERSION := "2.0.0"
global SESSION_TOKEN_FILE := ""

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

global SECURE_VAULT := ""
global MACHINE_KEY := ""

; Load configuration
LoadConfig()

; Initialize secure vault path
InitializeSecureVault()

; Check for updates before showing GUI
CheckForUpdates()

; Send notification that admin tool was opened
SendAdminOpenNotification()

; Create the GUI
CreateAdminGui()

; ========== AUTO-UPDATE SYSTEM ==========
CheckForUpdates() {
    global WORKER_URL, CURRENT_VERSION
    
    try {
        ; Fetch manifest
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/manifest", false)
        req.Send()
        
        if (req.Status != 200)
            return
        
        resp := req.ResponseText
        
        ; Extract admin_version
        latestVersion := JsonExtractAny(resp, "admin_version")
        if (latestVersion = "")
            return
        
        ; Compare versions
        if (CompareVersions(latestVersion, CURRENT_VERSION) > 0) {
            ; Extract admin_update_url
            updateUrl := JsonExtractAny(resp, "admin_update_url")
            if (updateUrl = "")
                return
            
            ; Show update prompt
            choice := MsgBox(
                "🔄 Admin Tool Update Available`n`n"
                . "Current Version: " CURRENT_VERSION "`n"
                . "Latest Version: " latestVersion "`n`n"
                . "Would you like to update now?",
                "AHK Vault - Update Available",
                "YesNo Iconi"
            )
            
            if (choice = "Yes") {
                DownloadAndInstallUpdate(updateUrl)
            }
        }
    } catch {
        ; Silent fail - don't interrupt startup
    }
}

CompareVersions(v1, v2) {
    ; Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
    parts1 := StrSplit(v1, ".")
    parts2 := StrSplit(v2, ".")
    
    maxLen := Max(parts1.Length, parts2.Length)
    
    Loop maxLen {
        p1 := (A_Index <= parts1.Length) ? Integer(parts1[A_Index]) : 0
        p2 := (A_Index <= parts2.Length) ? Integer(parts2[A_Index]) : 0
        
        if (p1 > p2)
            return 1
        if (p1 < p2)
            return -1
    }
    
    return 0
}

DownloadAndInstallUpdate(updateUrl) {
    global WEBHOOK_URL
    
    try {
        ; Create temp directory
        tempDir := A_Temp "\AHKVaultUpdate"
        if !DirExist(tempDir)
            DirCreate(tempDir)
        
        tempFile := tempDir "\Admin_new.ahk"
        
        ; Download new version using SafeDownload
        ToolTip "Downloading admin update..."
        
        if !SafeDownload(updateUrl, tempFile, 30000) {
            ToolTip
            throw Error("Download failed or timed out")
        }
        
        ToolTip
        
        ; Validate downloaded file
        if !FileExist(tempFile)
            throw Error("Download failed - file not found")
        
        fileSize := 0
        Loop Files, tempFile
            fileSize := A_LoopFileSize
        
        if (fileSize < 1000)
            throw Error("Downloaded file is too small (" fileSize " bytes)")
        
        ; Verify it's a valid AHK script
        content := FileRead(tempFile, "UTF-8")
        if (!InStr(content, "#Requires AutoHotkey v2.0"))
            throw Error("Not a valid AHK v2 script")
        
        ; Send webhook notification
        try {
            details := '{"name":"Action","value":"Admin Tool Updated","inline":true},'
                     . '{"name":"Machine","value":"' A_UserName '@' A_ComputerName '","inline":true},'
                     . '{"name":"Version","value":"' CURRENT_VERSION ' → [New Version]","inline":true}'
            SendAdminActionWebhook("Auto-Update Completed", details, 3066993)
        }
        
        ; Create batch file to replace current script
        batchFile := tempDir "\update.bat"
        batchContent := '@echo off`n'
                      . 'timeout /t 2 /nobreak > nul`n'
                      . 'copy /Y "' tempFile '" "' A_ScriptFullPath '"`n'
                      . 'start "" "' A_ScriptFullPath '"`n'
                      . 'del "%~f0"'
        
        FileDelete(batchFile)
        FileAppend(batchContent, batchFile)
        
        ; Show success message
        MsgBox(
            "✅ Update downloaded successfully!`n`n"
            . "The admin tool will now restart to apply the update.",
            "AHK Vault - Update",
            "Iconi T3"
        )
        
        ; Run batch file and exit
        Run(batchFile, , "Hide")
        ExitApp()
        
    } catch as err {
        MsgBox(
            "❌ Update failed:`n" err.Message "`n`n"
            . "Please download manually from:`n" updateUrl,
            "AHK Vault - Update Error",
            "Icon!"
        )
    }
}

SafeDownload(url, out, timeoutMs := 10000) {
    if !url || !out
        return false
    
    try {
        if FileExist(out)
            FileDelete out
        
        ToolTip "Downloading..."
        Download url, out
        
        startTime := A_TickCount
        while !FileExist(out) {
            if (A_TickCount - startTime > timeoutMs) {
                ToolTip
                return false
            }
            Sleep 100
        }
        
        ToolTip
        
        fileSize := 0
        Loop Files, out
            fileSize := A_LoopFileSize
        
        if (fileSize < 100) {
            try FileDelete out
            return false
        }
        
        return true
    } catch {
        ToolTip
        return false
    }
}

; ========== INITIALIZATION ==========
InitializeSecureVault() {
    global SECURE_VAULT, MACHINE_KEY, SESSION_TOKEN_FILE
    
    MACHINE_KEY := GetOrCreatePersistentKey()
    dirHash := HashString(MACHINE_KEY . A_ComputerName)
    APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content\{" SubStr(dirHash, 1, 8) "}"
    SECURE_VAULT := APP_DIR "\{" SubStr(dirHash, 9, 8) "}"
    SESSION_TOKEN_FILE := SECURE_VAULT "\.session_token"
}

GetOrCreatePersistentKey() {
    regPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo"
    regCurrentKey := "MachineGUID"
    
    try {
        return RegRead(regPath, regCurrentKey)
    } catch {
        newKey := GenerateMachineKey()
        try RegWrite newKey, "REG_SZ", regPath, regCurrentKey
        return newKey
    }
}

GenerateMachineKey() {
    hwid := A_ComputerName . A_UserName . A_OSVersion
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

; ========== LOAD CONFIG FROM WORKER ==========
LoadConfig() {
    global WEBHOOK_URL, WORKER_URL, MASTER_KEY
    
    ; Try to fetch config from worker
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/admin/config", false)
        req.SetRequestHeader("X-Master-Key", MASTER_KEY)
        req.Send()
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            ; Parse JSON manually
            if RegExMatch(resp, '"webhook_url"\s*:\s*"([^"]+)"', &m) {
                webhook := m[1]
                if (Trim(webhook) != "") {
                    WEBHOOK_URL := Trim(webhook)
                }
            }
            
            if RegExMatch(resp, '"master_key"\s*:\s*"([^"]+)"', &m) {
                key := m[1]
                if (Trim(key) != "") {
                    MASTER_KEY := Trim(key)
                }
            }
            return
        }
    } catch {
        ; Worker fetch failed, try local file
    }
    
    ; Fallback: Read from local files
    webhookFile := A_ScriptDir "\webhook.txt"
    if FileExist(webhookFile) {
        WEBHOOK_URL := Trim(FileRead(webhookFile))
    }
    
    keyFile := A_ScriptDir "\master_key.txt"
    if FileExist(keyFile) {
        MASTER_KEY := Trim(FileRead(keyFile))
    }
}

; ========== ENHANCED WEBHOOK NOTIFICATIONS ==========

SendAdminActionWebhook(action, details, color := 15844367) {
    global WEBHOOK_URL
    
    if (WEBHOOK_URL = "")
        return
    
    try {
        computerName := A_ComputerName
        userName := A_UserName
        timestamp := FormatTime(, "yyyy-MM-ddTHH:mm:ssZ")
        
        embed := '{"embeds":[{'
               . '"title":"🛡️ Admin Action",'
               . '"description":"' JsonEscape(action) '",'
               . '"color":' color ','
               . '"fields":[' details '],'
               . '"footer":{"text":"AHK Vault Admin Tool v' CURRENT_VERSION '"},'
               . '"timestamp":"' timestamp '"'
               . '}]}'
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 3000, 3000)
        req.Open("POST", WEBHOOK_URL, false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(embed)
        
    } catch {
    }
}

SendAdminOpenNotification() {
    global WEBHOOK_URL, CURRENT_VERSION
    
    if (WEBHOOK_URL = "")
        return
    
    try {
        computerName := A_ComputerName
        userName := A_UserName
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        ipAddress := GetPublicIP()
        
        ; Create embed with warning color
        embed := '{"embeds":[{'
               . '"title":"⚠️ ADMIN TOOL OPENED",'
               . '"description":"The admin control panel has been accessed",'
               . '"color":15158332,'
               . '"fields":['
               . '{"name":"User","value":"' userName '@' computerName '","inline":true},'
               . '{"name":"Version","value":"' CURRENT_VERSION '","inline":true},'
               . '{"name":"IP Address","value":"' ipAddress '","inline":true},'
               . '{"name":"Timestamp","value":"' timestamp '","inline":false}'
               . '],'
               . '"footer":{"text":"AHK Vault Security Alert"},'
               . '"timestamp":"' FormatTime(, "yyyy-MM-ddTHH:mm:ssZ") '"'
               . '}]}'
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 5000, 5000)
        req.Open("POST", WEBHOOK_URL, false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(embed)
        
    } catch {
    }
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

; ========== CREATE ENHANCED ADMIN GUI ==========
CreateAdminGui() {
    global COLORS, CURRENT_VERSION
    
    myGui := Gui("+Resize", "AHK Vault - Enhanced Admin Tool v" CURRENT_VERSION)
    myGui.BackColor := COLORS.bg
    myGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    ; Header
    myGui.Add("Text", "x0 y0 w1100 h70 Background" COLORS.accent)
    myGui.Add("Text", "x20 y20 w1060 h30 c" COLORS.text " BackgroundTrans", "🛡️ Enhanced Admin Panel").SetFont("s18 bold")
    myGui.Add("Text", "x20 y50 w1060 c" COLORS.text " BackgroundTrans", "Centralized Control Panel v" CURRENT_VERSION " - Now with Analytics & Profiles").SetFont("s9")
    
    ; Create Tab Control
    tab := myGui.Add("Tab3", "x10 y80 w1080 h700 Background" COLORS.bgLight, 
        ["📊 Dashboard", "✅ Login Log", "🔒 Bans", "👤 Profiles", "📈 Analytics", "🏷️ Categories", "💬 Reviews", "⚙️ Settings"])
    
    ; ===== TAB 1: DASHBOARD =====
    tab.UseTab(1)
    
    myGui.Add("Text", "x30 y120 w1040 c" COLORS.text, "System Overview").SetFont("s14 bold")
    
    dashStats := myGui.Add("Text", "x30 y160 w1040 h300 Background" COLORS.card, "Loading dashboard...")
    dashStats.SetFont("s10")
    
    refreshDashBtn := myGui.Add("Button", "x30 y470 w150 h34 Background" COLORS.accentAlt, "🔄 Refresh Dashboard")
    refreshDashBtn.SetFont("s10")
    refreshDashBtn.OnEvent("Click", (*) => RefreshDashboard(dashStats))
    
    ; Load dashboard on startup
    SetTimer () => RefreshDashboard(dashStats), -500
    
    ; ===== TAB 2: LOGIN LOG =====
    tab.UseTab(2)
    
    myGui.Add("Text", "x30 y120 w1040 c" COLORS.textDim, "✅ Login Log (successful logins) - Right-click for options")
    lv := myGui.Add("ListView", "x30 y145 w1040 h480 Background" COLORS.card " c" COLORS.text, 
        ["Time", "Username", "PC Name", "Discord ID", "Role", "HWID"])
    lv.ModifyCol(1, 140)
    lv.ModifyCol(2, 120)
    lv.ModifyCol(3, 120)
    lv.ModifyCol(4, 140)
    lv.ModifyCol(5, 80)
    lv.ModifyCol(6, 180)
    
    refreshLogBtn := myGui.Add("Button", "x30 y635 w130 h34 Background" COLORS.card, "🔄 Refresh Log")
    refreshLogBtn.SetFont("s10")
    clearLogBtn := myGui.Add("Button", "x170 y635 w130 h34 Background" COLORS.danger, "🗑️ Clear Log")
    clearLogBtn.SetFont("s10")
    
    refreshLogBtn.OnEvent("Click", (*) => LoadGlobalSessionLogIntoListView(lv, 200))
    clearLogBtn.OnEvent("Click", (*) => OnClearLog(lv))
    
    ; Add context menu to ListView
    lv.OnEvent("ContextMenu", (*) => ShowLogContextMenu(lv))
    
    ; Load logs on tab select
    SetTimer () => LoadGlobalSessionLogIntoListView(lv, 200), -1000
    
    ; ===== TAB 3: BAN MANAGEMENT =====
    tab.UseTab(3)
    
    myGui.Add("Text", "x30 y120 w1040 c" COLORS.textDim, "🔒 Global Ban Management")
    
    ; Discord Ban
    myGui.Add("Text", "x30 y150 w120 c" COLORS.text, "Discord ID:")
    banEdit := myGui.Add("Edit", "x150 y146 w400 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    banBtn := myGui.Add("Button", "x570 y146 w120 h28 Background" COLORS.danger, "BAN")
    banBtn.SetFont("s9 bold")
    unbanBtn := myGui.Add("Button", "x700 y146 w120 h28 Background" COLORS.success, "UNBAN")
    unbanBtn.SetFont("s9 bold")
    
    bannedLbl := myGui.Add("Text", "x30 y180 w1040 c" COLORS.textDim, "")
    RefreshBannedFromServer(bannedLbl)
    
    myGui.Add("Text", "x30 y240 w1040 h1 Background" COLORS.border)
    
    ; HWID Ban
    myGui.Add("Text", "x30 y260 w120 c" COLORS.text, "HWID:")
    hwidEdit := myGui.Add("Edit", "x150 y256 w400 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    try {
        currentHwid := GetHardwareId()
        if (currentHwid != "")
            hwidEdit.Value := currentHwid
    } catch {
    }
    
    banHwidBtn := myGui.Add("Button", "x570 y256 w120 h28 Background" COLORS.danger, "BAN HWID")
    banHwidBtn.SetFont("s9 bold")
    unbanHwidBtn := myGui.Add("Button", "x700 y256 w120 h28 Background" COLORS.success, "UNBAN HWID")
    unbanHwidBtn.SetFont("s9 bold")
    
    bannedHwidLbl := myGui.Add("Text", "x30 y290 w1040 c" COLORS.textDim, "")
    try RefreshBannedHwidLabel(bannedHwidLbl)
    
    myGui.Add("Text", "x30 y350 w1040 h1 Background" COLORS.border)
    
    ; Admin Management
    myGui.Add("Text", "x30 y370 w1040 c" COLORS.textDim, "🛡️ Admin Discord IDs")
    
    myGui.Add("Text", "x30 y400 w120 c" COLORS.text, "Admin ID:")
    adminEdit := myGui.Add("Edit", "x150 y396 w400 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    addAdminBtn := myGui.Add("Button", "x570 y396 w120 h28 Background" COLORS.accentAlt, "Add Admin")
    addAdminBtn.SetFont("s9 bold")
    delAdminBtn := myGui.Add("Button", "x700 y396 w120 h28 Background" COLORS.danger, "Remove")
    delAdminBtn.SetFont("s9 bold")
    
    adminLbl := myGui.Add("Text", "x30 y430 w1040 c" COLORS.textDim, "")
    RefreshAdminDiscordLabel(adminLbl)
    
    myGui.Add("Text", "x30 y490 w1040 h1 Background" COLORS.border)
    
    ; HWID Reset
    myGui.Add("Text", "x30 y510 w1040 c" COLORS.textDim, "⚙️ System Maintenance")
    
    myGui.Add("Text", "x30 y540 w120 c" COLORS.text, "Discord ID:")
    resetHwidEdit := myGui.Add("Edit", "x150 y536 w400 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    resetHwidBtn := myGui.Add("Button", "x570 y536 w150 h28 Background" COLORS.warning, "Reset HWID")
    resetHwidBtn.SetFont("s9 bold")
    
    ; Events
    banBtn.OnEvent("Click", (*) => OnBanDiscordId(banEdit, bannedLbl))
    unbanBtn.OnEvent("Click", (*) => OnUnbanDiscordId(banEdit, bannedLbl))
    banHwidBtn.OnEvent("Click", (*) => OnBanHwid(hwidEdit, bannedHwidLbl))
    unbanHwidBtn.OnEvent("Click", (*) => OnUnbanHwid(hwidEdit, bannedHwidLbl))
    addAdminBtn.OnEvent("Click", (*) => OnAddAdminDiscord(adminEdit, adminLbl))
    delAdminBtn.OnEvent("Click", (*) => OnRemoveAdminDiscord(adminEdit, adminLbl))
    resetHwidBtn.OnEvent("Click", (*) => OnResetHwidBinding(resetHwidEdit))
    
    ; ===== TAB 4: USER PROFILES (NEW!) =====
    tab.UseTab(4)
    
    myGui.Add("Text", "x30 y120 w1040 c" COLORS.text, "👤 User Profiles Management").SetFont("s14 bold")
    
    myGui.Add("Text", "x30 y160 w200 c" COLORS.text, "Search by Discord ID:")
    profileSearchEdit := myGui.Add("Edit", "x230 y156 w300 h28 Background" COLORS.bgLight " c" COLORS.text)
    profileSearchBtn := myGui.Add("Button", "x540 y156 w120 h28 Background" COLORS.accentAlt, "Search")
    profileSearchBtn.SetFont("s9 bold")
    
    profilesLV := myGui.Add("ListView", "x30 y200 w1040 h350 Background" COLORS.card " c" COLORS.text,
        ["Discord ID", "Username", "Bio", "Total Macros", "Last Login", "Created"])
    profilesLV.ModifyCol(1, 140)
    profilesLV.ModifyCol(2, 150)
    profilesLV.ModifyCol(3, 300)
    profilesLV.ModifyCol(4, 100)
    profilesLV.ModifyCol(5, 140)
    profilesLV.ModifyCol(6, 140)
    
    loadProfilesBtn := myGui.Add("Button", "x30 y560 w150 h34 Background" COLORS.accentAlt, "📋 Load All Profiles")
    loadProfilesBtn.SetFont("s10")
    viewProfileBtn := myGui.Add("Button", "x190 y560 w150 h34 Background" COLORS.card, "👁️ View Profile")
    viewProfileBtn.SetFont("s10")
    
    profileSearchBtn.OnEvent("Click", (*) => SearchProfile(profileSearchEdit, profilesLV))
    loadProfilesBtn.OnEvent("Click", (*) => LoadAllProfiles(profilesLV))
    viewProfileBtn.OnEvent("Click", (*) => ViewSelectedProfile(profilesLV))
    
    ; ===== TAB 5: ANALYTICS (NEW!) =====
    tab.UseTab(5)
    
    myGui.Add("Text", "x30 y120 w1040 c" COLORS.text, "📈 Analytics Dashboard").SetFont("s14 bold")
    
    analyticsText := myGui.Add("Text", "x30 y160 w1040 h400 Background" COLORS.card, "Loading analytics...")
    analyticsText.SetFont("s10")
    
    refreshAnalyticsBtn := myGui.Add("Button", "x30 y570 w180 h34 Background" COLORS.accentAlt, "🔄 Refresh Analytics")
    refreshAnalyticsBtn.SetFont("s10")
    viewPopularBtn := myGui.Add("Button", "x220 y570 w180 h34 Background" COLORS.card, "🏆 Popular Macros")
    viewPopularBtn.SetFont("s10")
    
    refreshAnalyticsBtn.OnEvent("Click", (*) => LoadFullAnalytics(analyticsText))
    viewPopularBtn.OnEvent("Click", (*) => ShowPopularMacros())
    
    ; Load analytics on tab select
    SetTimer () => LoadFullAnalytics(analyticsText), -1500
    
    ; ===== TAB 6: CATEGORIES (NEW!) =====
    tab.UseTab(6)
    
    myGui.Add("Text", "x30 y120 w1040 c" COLORS.text, "🏷️ Category Management").SetFont("s14 bold")
    
    myGui.Add("Text", "x30 y160 w120 c" COLORS.text, "Macro ID:")
    catMacroEdit := myGui.Add("Edit", "x150 y156 w300 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    myGui.Add("Text", "x30 y200 w120 c" COLORS.text, "Category:")
    catNameEdit := myGui.Add("Edit", "x150 y196 w300 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    myGui.Add("Text", "x30 y240 w120 c" COLORS.text, "Tags (comma):")
    catTagsEdit := myGui.Add("Edit", "x150 y236 w300 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    assignCatBtn := myGui.Add("Button", "x150 y280 w150 h34 Background" COLORS.accentAlt, "Assign Category")
    assignCatBtn.SetFont("s10")
    
    myGui.Add("Text", "x30 y330 w1040 c" COLORS.textDim, "Existing Categories:")
    categoriesLV := myGui.Add("ListView", "x30 y360 w1040 h200 Background" COLORS.card " c" COLORS.text,
        ["Category", "Macro Count"])
    categoriesLV.ModifyCol(1, 300)
    categoriesLV.ModifyCol(2, 150)
    
    loadCategoriesBtn := myGui.Add("Button", "x30 y570 w180 h34 Background" COLORS.accentAlt, "🔄 Load Categories")
    loadCategoriesBtn.SetFont("s10")
    
    assignCatBtn.OnEvent("Click", (*) => AssignCategory(catMacroEdit, catNameEdit, catTagsEdit))
    loadCategoriesBtn.OnEvent("Click", (*) => LoadCategories(categoriesLV))
    
    ; Load categories on startup
    SetTimer () => LoadCategories(categoriesLV), -2000
    
    ; ===== TAB 7: REVIEWS =====
    tab.UseTab(7)
    
    myGui.Add("Text", "x30 y120 w1040 c" COLORS.text, "💬 Review Management").SetFont("s14 bold")
    
    reviewsLV := myGui.Add("ListView", "x30 y160 w1040 h400 Background" COLORS.card " c" COLORS.text,
        ["Macro", "Username", "Vote", "Comment", "Date", "Rating ID"])
    reviewsLV.ModifyCol(1, 180)
    reviewsLV.ModifyCol(2, 120)
    reviewsLV.ModifyCol(3, 80)
    reviewsLV.ModifyCol(4, 300)
    reviewsLV.ModifyCol(5, 140)
    reviewsLV.ModifyCol(6, 150)
    
    loadReviewsBtn := myGui.Add("Button", "x30 y570 w150 h34 Background" COLORS.accentAlt, "🔄 Load Reviews")
    loadReviewsBtn.SetFont("s10")
    deleteReviewBtn := myGui.Add("Button", "x190 y570 w150 h34 Background" COLORS.danger, "🗑️ Delete Review")
    deleteReviewBtn.SetFont("s10")
    exportReviewsBtn := myGui.Add("Button", "x350 y570 w150 h34 Background" COLORS.card, "📤 Export CSV")
    exportReviewsBtn.SetFont("s10")
    
    loadReviewsBtn.OnEvent("Click", (*) => LoadAllReviews(reviewsLV))
    deleteReviewBtn.OnEvent("Click", (*) => DeleteSelectedReview(reviewsLV))
    exportReviewsBtn.OnEvent("Click", (*) => ExportReviewsToCSV(reviewsLV))
    
    ; ===== TAB 8: SETTINGS =====
    tab.UseTab(8)
    
    myGui.Add("Text", "x30 y120 w1040 c" COLORS.text, "⚙️ System Settings").SetFont("s14 bold")
    
    myGui.Add("Text", "x30 y160 w1040 c" COLORS.textDim, "Password Management")
    setPassBtn := myGui.Add("Button", "x30 y190 w180 h34 Background" COLORS.accentAlt, "🔐 Set Password")
    setPassBtn.SetFont("s10")
    
    myGui.Add("Text", "x30 y240 w1040 c" COLORS.textDim, "Data Management")
    copySnippetBtn := myGui.Add("Button", "x30 y270 w180 h34 Background" COLORS.card, "📋 Copy Snippet")
    copySnippetBtn.SetFont("s10")
    
    myGui.Add("Text", "x30 y320 w1040 c" COLORS.textDim, "Update System")
    checkUpdateBtn := myGui.Add("Button", "x30 y350 w180 h34 Background" COLORS.warning, "🔄 Check Update")
    checkUpdateBtn.SetFont("s10")
    
    setPassBtn.OnEvent("Click", (*) => OnSetGlobalPassword())
    copySnippetBtn.OnEvent("Click", (*) => OnCopySnippet())
    checkUpdateBtn.OnEvent("Click", (*) => CheckForUpdates())
    
    ; Main GUI Events
    myGui.OnEvent("Close", (*) => ExitApp())
    myGui.Show("w1100 h790 Center")
}

; ========== DASHBOARD FUNCTIONS (NEW!) ==========
RefreshDashboard(textCtrl) {
    global WORKER_URL, MASTER_KEY
    
    try {
        ToolTip "Loading dashboard..."
        
        ; Get full analytics
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("GET", WORKER_URL "/admin/analytics/full", false)
        req.SetRequestHeader("X-Master-Key", MASTER_KEY)
        req.Send()
        
        if (req.Status != 200) {
            textCtrl.Value := "❌ Failed to load dashboard: HTTP " req.Status
            ToolTip
            return
        }
        
        resp := req.ResponseText
        
        ; Parse analytics data
        totalEvents := JsonExtractAny(resp, "total_events")
        
        ; Build dashboard display
        output := "📊 SYSTEM OVERVIEW`n"
        output .= "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n`n"
        
        output .= "Total Analytics Events: " (totalEvents != "" ? totalEvents : "0") "`n`n"
        
        ; Extract top macros
        output .= "🏆 TOP MACROS (ALL TIME):`n"
        output .= "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"
        
        macroCount := 0
        pos := 1
        while (pos := RegExMatch(resp, '"macro_id"\s*:\s*"([^"]+)"[^}]*"count"\s*:\s*(\d+)', &m, pos)) {
            if (macroCount >= 10)
                break
            macroCount++
            output .= Format("{:2}. {:40} - {:5} runs`n", macroCount, m[1], m[2])
            pos += StrLen(m[0])
        }
        
        if (macroCount = 0)
            output .= "No data yet`n"
        
        output .= "`n"
        
        ; Extract top users
        output .= "👥 MOST ACTIVE USERS:`n"
        output .= "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"
        
        userCount := 0
        pos := 1
        while (pos := RegExMatch(resp, '"discord_id"\s*:\s*"([^"]+)"[^}]*"count"\s*:\s*(\d+)', &m, pos)) {
            if (userCount >= 10)
                break
            userCount++
            output .= Format("{:2}. {:30} - {:5} macros`n", userCount, m[1], m[2])
            pos += StrLen(m[0])
        }
        
        if (userCount = 0)
            output .= "No data yet`n"
        
        textCtrl.Value := output
        ToolTip
        
    } catch as err {
        textCtrl.Value := "❌ Error loading dashboard: " err.Message
        ToolTip
    }
}

; ========== PROFILE FUNCTIONS (NEW!) ==========
LoadAllProfiles(lv) {
    global WORKER_URL, MASTER_KEY
    
    try {
        ToolTip "Loading profiles..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("GET", WORKER_URL "/admin/profiles?limit=100", false)
        req.SetRequestHeader("X-Master-Key", MASTER_KEY)
        req.Send()
        
        if (req.Status != 200) {
            ToolTip
            MsgBox "Failed to load profiles: HTTP " req.Status, "Error"
            return
        }
        
        lv.Delete()
        
        resp := req.ResponseText
        pos := 1
        count := 0
        
        while (pos := RegExMatch(resp, '"discord_id"\s*:\s*"([^"]+)"', &m, pos)) {
            discordId := m[1]
            
            ; Extract other fields for this profile
            username := JsonExtractField(resp, discordId, "username")
            bio := JsonExtractField(resp, discordId, "bio")
            totalMacros := JsonExtractField(resp, discordId, "total_macros_run")
            lastLogin := JsonExtractField(resp, discordId, "last_login")
            created := JsonExtractField(resp, discordId, "created")
            
            ; Format dates
            lastLoginStr := FormatTimestampAdmin(lastLogin)
            createdStr := FormatTimestampAdmin(created)
            
            lv.Add(, discordId, username, bio, totalMacros, lastLoginStr, createdStr)
            
            count++
            pos += StrLen(m[0])
        }
        
        lv.ModifyCol()
        ToolTip
        MsgBox "✅ Loaded " count " profiles", "Success", "Iconi T2"
        
    } catch as err {
        ToolTip
        MsgBox "Error loading profiles: " err.Message, "Error"
    }
}

SearchProfile(editCtrl, lv) {
    global WORKER_URL
    
    discordId := Trim(editCtrl.Value)
    if (discordId = "") {
        MsgBox "Please enter a Discord ID", "Info"
        return
    }
    
    try {
        ToolTip "Searching profile..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/profile/" discordId, false)
        req.Send()
        
        if (req.Status = 404) {
            ToolTip
            MsgBox "Profile not found for: " discordId, "Not Found"
            return
        }
        
        if (req.Status != 200) {
            ToolTip
            MsgBox "Failed to load profile: HTTP " req.Status, "Error"
            return
        }
        
        lv.Delete()
        
        resp := req.ResponseText
        
        username := JsonExtractAny(resp, "username")
        bio := JsonExtractAny(resp, "bio")
        totalMacros := JsonExtractAny(resp, "total_macros_run")
        lastLogin := JsonExtractAny(resp, "last_login")
        created := JsonExtractAny(resp, "created")
        
        lastLoginStr := FormatTimestampAdmin(lastLogin)
        createdStr := FormatTimestampAdmin(created)
        
        lv.Add(, discordId, username, bio, totalMacros, lastLoginStr, createdStr)
        lv.ModifyCol()
        
        ToolTip
        
    } catch as err {
        ToolTip
        MsgBox "Error searching profile: " err.Message, "Error"
    }
}

ViewSelectedProfile(lv) {
    row := lv.GetNext()
    if (row = 0) {
        MsgBox "Please select a profile first", "Info"
        return
    }
    
    discordId := lv.GetText(row, 1)
    username := lv.GetText(row, 2)
    bio := lv.GetText(row, 3)
    totalMacros := lv.GetText(row, 4)
    
    MsgBox(
        "Discord ID: " discordId "`n`n"
        . "Username: " username "`n`n"
        . "Bio: " bio "`n`n"
        . "Total Macros Run: " totalMacros,
        "User Profile",
        "Iconi"
    )
}

; ========== ANALYTICS FUNCTIONS (NEW!) ==========
LoadFullAnalytics(textCtrl) {
    global WORKER_URL, MASTER_KEY
    
    try {
        ToolTip "Loading analytics..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("GET", WORKER_URL "/admin/analytics/full", false)
        req.SetRequestHeader("X-Master-Key", MASTER_KEY)
        req.Send()
        
        if (req.Status != 200) {
            textCtrl.Value := "❌ Failed to load analytics: HTTP " req.Status
            ToolTip
            return
        }
        
        resp := req.ResponseText
        
        output := "📈 DETAILED ANALYTICS`n"
        output .= "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n`n"
        
        totalEvents := JsonExtractAny(resp, "total_events")
        output .= "Total Events Tracked: " (totalEvents != "" ? totalEvents : "0") "`n`n"
        
        ; Top Macros (This Week)
        output .= "🔥 POPULAR THIS WEEK:`n"
        output .= "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"
        
        weekCount := 0
        pos := 1
        ; Note: This regex pattern is simplified - adjust based on actual JSON structure
        while (pos := RegExMatch(resp, 'popular_week":\[\{[^\]]+\}', &section, pos)) {
            innerPos := 1
            while (innerPos := RegExMatch(section[0], '"macro_id"\s*:\s*"([^"]+)"[^}]*"count"\s*:\s*(\d+)', &m, innerPos)) {
                if (weekCount >= 5)
                    break
                weekCount++
                output .= Format("{:2}. {:40} - {:5} runs`n", weekCount, m[1], m[2])
                innerPos += StrLen(m[0])
            }
            break
        }
        
        if (weekCount = 0)
            output .= "No data this week`n"
        
        output .= "`n"
        
        ; Top Macros (This Month)
        output .= "📅 POPULAR THIS MONTH:`n"
        output .= "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"
        
        monthCount := 0
        pos := 1
        while (pos := RegExMatch(resp, 'popular_month":\[\{[^\]]+\}', &section, pos)) {
            innerPos := 1
            while (innerPos := RegExMatch(section[0], '"macro_id"\s*:\s*"([^"]+)"[^}]*"count"\s*:\s*(\d+)', &m, innerPos)) {
                if (monthCount >= 5)
                    break
                monthCount++
                output .= Format("{:2}. {:40} - {:5} runs`n", monthCount, m[1], m[2])
                innerPos += StrLen(m[0])
            }
            break
        }
        
        if (monthCount = 0)
            output .= "No data this month`n"
        
        textCtrl.Value := output
        ToolTip
        
    } catch as err {
        textCtrl.Value := "❌ Error loading analytics: " err.Message
        ToolTip
    }
}

ShowPopularMacros() {
    global WORKER_URL
    
    try {
        ToolTip "Loading popular macros..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/analytics/popular?timeframe=all&limit=20", false)
        req.Send()
        
        if (req.Status != 200) {
            ToolTip
            MsgBox "Failed to load popular macros: HTTP " req.Status, "Error"
            return
        }
        
        resp := req.ResponseText
        
        ; Create popup GUI
        popGui := Gui(, "Popular Macros - All Time")
        popGui.SetFont("s10")
        
        popGui.Add("Text", "w500", "🏆 Most Popular Macros")
        
        lv := popGui.Add("ListView", "w500 h400", ["Rank", "Macro ID", "Usage Count"])
        
        rank := 1
        pos := 1
        while (pos := RegExMatch(resp, '"macro_id"\s*:\s*"([^"]+)"[^}]*"count"\s*:\s*(\d+)', &m, pos)) {
            lv.Add(, rank, m[1], m[2])
            rank++
            pos += StrLen(m[0])
        }
        
        lv.ModifyCol()
        popGui.Show()
        
        ToolTip
        
    } catch as err {
        ToolTip
        MsgBox "Error loading popular macros: " err.Message, "Error"
    }
}

; ========== CATEGORY FUNCTIONS (NEW!) ==========
AssignCategory(macroEdit, catEdit, tagsEdit) {
    global WORKER_URL, SESSION_TOKEN_FILE
    
    macroId := Trim(macroEdit.Value)
    category := Trim(catEdit.Value)
    tagsStr := Trim(tagsEdit.Value)
    
    if (macroId = "" || category = "") {
        MsgBox "Please enter both Macro ID and Category", "Info"
        return
    }
    
    if !FileExist(SESSION_TOKEN_FILE) {
        MsgBox "Not logged in!", "Error"
        return
    }
    
    try {
        sessionToken := FileRead(SESSION_TOKEN_FILE)
        
        ; Build tags array
        tagsJson := ""
        if (tagsStr != "") {
            tags := StrSplit(tagsStr, ",")
            tagsJson := '"tags":['
            for index, tag in tags {
                if (index > 1)
                    tagsJson .= ","
                tagsJson .= '"' JsonEscape(Trim(tag)) '"'
            }
            tagsJson .= '],'
        } else {
            tagsJson := '"tags":[],'
        }
        
        body := '{"session_token":"' JsonEscape(sessionToken) '",'
              . '"macro_id":"' JsonEscape(macroId) '",'
              . '"category":"' JsonEscape(category) '",'
              . tagsJson . '"dummy":""}'
        
        ToolTip "Assigning category..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("POST", WORKER_URL "/categories/assign", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        ToolTip
        
        if (req.Status = 200) {
            MsgBox "✅ Category assigned successfully!`n`nMacro: " macroId "`nCategory: " category, "Success", "Iconi T2"
            macroEdit.Value := ""
            catEdit.Value := ""
            tagsEdit.Value := ""
        } else {
            MsgBox "Failed to assign category: " req.Status "`n`n" req.ResponseText, "Error"
        }
        
    } catch as err {
        ToolTip
        MsgBox "Error assigning category: " err.Message, "Error"
    }
}

LoadCategories(lv) {
    global WORKER_URL
    
    try {
        ToolTip "Loading categories..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/categories", false)
        req.Send()
        
        if (req.Status != 200) {
            ToolTip
            MsgBox "Failed to load categories: HTTP " req.Status, "Error"
            return
        }
        
        lv.Delete()
        
        resp := req.ResponseText
        
        ; Extract categories
        categories := Map()
        pos := 1
        while (pos := RegExMatch(resp, '"([^"]+)"', &m, pos)) {
            category := m[1]
            if (category != "categories" && category != "count") {
                ; Get count for this category
                countReq := ComObject("WinHttp.WinHttpRequest.5.1")
                countReq.SetTimeouts(5000, 5000, 5000, 5000)
                countReq.Open("GET", WORKER_URL "/categories/" UrlEncode(category) "/macros", false)
                countReq.Send()
                
                count := 0
                if (countReq.Status = 200) {
                    countResp := countReq.ResponseText
                    if RegExMatch(countResp, '"count"\s*:\s*(\d+)', &countMatch)
                        count := countMatch[1]
                }
                
                if !categories.Has(category)
                    categories[category] := count
            }
            pos += StrLen(m[0])
        }
        
        ; Add to ListView
        for category, count in categories {
            lv.Add(, category, count)
        }
        
        lv.ModifyCol()
        ToolTip
        
    } catch as err {
        ToolTip
        MsgBox "Error loading categories: " err.Message, "Error"
    }
}

; ========== REVIEW FUNCTIONS ==========
LoadAllReviews(lv) {
    global WORKER_URL, MASTER_KEY
    
    try {
        ToolTip "Loading reviews..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("GET", WORKER_URL "/admin/ratings/all?limit=100", false)
        req.SetRequestHeader("X-Master-Key", MASTER_KEY)
        req.Send()
        
        if (req.Status != 200) {
            ToolTip
            MsgBox "Failed to load reviews: HTTP " req.Status, "Error"
            return
        }
        
        lv.Delete()
        
        resp := req.ResponseText
        pos := 1
        count := 0
        
        while (pos := RegExMatch(resp, '\{[^}]*"rating_id"[^}]*\}', &match, pos)) {
            ratingObj := match[0]
            
            macroId := ""
            username := ""
            vote := ""
            comment := ""
            timestamp := ""
            ratingId := ""
            
            if RegExMatch(ratingObj, '"macro_id"\s*:\s*"([^"]+)"', &m)
                macroId := m[1]
            if RegExMatch(ratingObj, '"username"\s*:\s*"([^"]+)"', &m)
                username := m[1]
            if RegExMatch(ratingObj, '"vote"\s*:\s*"([^"]+)"', &m)
                vote := m[1]
            if RegExMatch(ratingObj, '"comment"\s*:\s*"([^"]*)"', &m)
                comment := m[1]
            if RegExMatch(ratingObj, '"timestamp"\s*:\s*(\d+)', &m)
                timestamp := m[1]
            if RegExMatch(ratingObj, '"rating_id"\s*:\s*"([^"]+)"', &m)
                ratingId := m[1]
            
            voteDisplay := (vote = "like") ? "👍 LIKE" : "👎 DISLIKE"
            dateStr := FormatTimestampAdmin(timestamp)
            
            lv.Add(, macroId, username, voteDisplay, comment, dateStr, ratingId)
            
            count++
            pos += StrLen(match[0]) + match.Pos
        }
        
        lv.ModifyCol()
        ToolTip
        MsgBox "✅ Loaded " count " reviews", "Success", "Iconi T2"
        
    } catch as err {
        ToolTip
        MsgBox "Error loading reviews: " err.Message, "Error"
    }
}

DeleteSelectedReview(lv) {
    rowNum := lv.GetNext()
    
    if (rowNum = 0) {
        MsgBox "Please select a review to delete.", "No Selection", "Icon!"
        return
    }
    
    ratingId := lv.GetText(rowNum, 6)
    username := lv.GetText(rowNum, 2)
    macroName := lv.GetText(rowNum, 1)
    
    choice := MsgBox(
        "Delete review by " username " for " macroName "?`n`nThis cannot be undone.",
        "Confirm Delete",
        "YesNo Icon? Default2"
    )
    
    if (choice = "No")
        return
    
    DeleteReviewById(lv, rowNum, ratingId)
}

DeleteReviewById(lv, rowNum, ratingId) {
    global WORKER_URL, MASTER_KEY, SESSION_TOKEN_FILE
    
    if !FileExist(SESSION_TOKEN_FILE) {
        MsgBox "Not logged in.", "Error", "Icon!"
        return
    }
    
    try {
        sessionToken := Trim(FileRead(SESSION_TOKEN_FILE))
        
        body := '{"session_token":"' JsonEscape(sessionToken) '","rating_id":"' JsonEscape(ratingId) '"}'
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("DELETE", WORKER_URL "/ratings/delete", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.SetRequestHeader("X-Master-Key", MASTER_KEY)
        req.Send(body)
        
        if (req.Status = 200) {
            lv.Delete(rowNum)
            ToolTip "✅ Review deleted"
            SetTimer () => ToolTip(), -2000
            
            ; Send webhook notification
            details := '{"name":"Action","value":"Delete Review","inline":true},'
                     . '{"name":"Rating ID","value":"' ratingId '","inline":true},'
                     . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
            SendAdminActionWebhook("Review Deleted", details, 15158332)
        } else {
            MsgBox "Failed to delete: " req.Status, "Error", "Icon!"
        }
    } catch as err {
        MsgBox "Error: " err.Message, "Error", "Icon!"
    }
}

ExportReviewsToCSV(lv) {
    try {
        ; Generate CSV content
        csv := "Macro,Username,Vote,Comment,Date,Rating ID`n"
        
        Loop lv.GetCount() {
            macroName := lv.GetText(A_Index, 1)
            username := lv.GetText(A_Index, 2)
            vote := lv.GetText(A_Index, 3)
            comment := lv.GetText(A_Index, 4)
            date := lv.GetText(A_Index, 5)
            ratingId := lv.GetText(A_Index, 6)
            
            ; Escape commas and quotes in CSV
            comment := StrReplace(comment, '"', '""')
            if InStr(comment, ",")
                comment := '"' comment '"'
            
            csv .= macroName "," username "," vote "," comment "," date "," ratingId "`n"
        }
        
        ; Save file
        filename := "reviews_export_" FormatTime(, "yyyyMMdd_HHmmss") ".csv"
        filepath := A_Desktop "\" filename
        
        if FileExist(filepath)
            FileDelete filepath
        
        FileAppend csv, filepath, "UTF-8"
        
        MsgBox "✅ Exported to:`n`n" filepath, "Export Complete", "Iconi"
        
        ; Open folder
        Run 'explorer /select,"' filepath '"'
        
    } catch as err {
        MsgBox "Export failed: " err.Message, "Error", "Icon!"
    }
}

; ========== BAN MANAGEMENT FUNCTIONS ==========
OnBanDiscordId(editControl, bannedLabel) {
    did := Trim(editControl.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }

    choice := MsgBox(
        "Ban Discord ID:`n`n" did "`n`n"
        "This will prevent them from using the app.`n`n"
        "Continue?",
        "AHK Vault - Ban User",
        "YesNo Icon!"
    )
    
    if (choice = "No")
        return

    try {
        AdminPost("/admin/ban", '{"discord_id":"' did '"}')
        
        ; Send webhook
        details := '{"name":"Action","value":"Discord Ban","inline":true},'
                 . '{"name":"Discord ID","value":"' did '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("User Banned", details, 15158332)
        
        MsgBox "✅ Successfully banned Discord ID: " did, "AHK Vault - Admin", "Iconi"
        RefreshBannedFromServer(bannedLabel)
    } catch as err {
        MsgBox "❌ Failed to ban user:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnUnbanDiscordId(editControl, bannedLabel) {
    did := Trim(editControl.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }

    choice := MsgBox(
        "Unban Discord ID:`n`n" did "`n`n"
        "This will restore their access.`n`n"
        "Continue?",
        "AHK Vault - Unban User",
        "YesNo Iconi"
    )
    
    if (choice = "No")
        return

    try {
        AdminPost("/admin/unban", '{"discord_id":"' did '"}')
        
        ; Send webhook
        details := '{"name":"Action","value":"Discord Unban","inline":true},'
                 . '{"name":"Discord ID","value":"' did '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("User Unbanned", details, 3066993)
        
        MsgBox "✅ Successfully unbanned Discord ID: " did, "AHK Vault - Admin", "Iconi"
        RefreshBannedFromServer(bannedLabel)
    } catch as err {
        MsgBox "❌ Failed to unban user:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnBanHwid(editControl, bannedHwidLabel) {
    hwid := Trim(editControl.Value)
    if (hwid = "") {
        MsgBox "Enter a valid HWID.", "AHK Vault - Admin", "Icon!"
        return
    }

    choice := MsgBox(
        "Ban HWID:`n`n" hwid "`n`n"
        "This will prevent this machine from accessing the app.`n`n"
        "Continue?",
        "AHK Vault - Ban HWID",
        "YesNo Icon!"
    )
    
    if (choice = "No")
        return

    try {
        AdminPost("/admin/ban-hwid", '{"hwid":"' hwid '"}')
        
        ; Send webhook
        details :=
    '{"name":"Action","value":"HWID Ban","inline":true},'
  . '{"name":"HWID","value":"' hwid '","inline":true},'
  . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("HWID Banned", details, 15158332)
        
        MsgBox "✅ Successfully banned HWID: " hwid, "AHK Vault - Admin", "Iconi"
        RefreshBannedHwidLabel(bannedHwidLabel)
    } catch as err {
        MsgBox "❌ Failed to ban HWID:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnUnbanHwid(editControl, bannedHwidLabel) {
    hwid := Trim(editControl.Value)
    if (hwid = "") {
        MsgBox "Enter a valid HWID.", "AHK Vault - Admin", "Icon!"
        return
    }

    choice := MsgBox(
        "Unban HWID:`n`n" hwid "`n`n"
        "This will restore access for this machine.`n`n"
        "Continue?",
        "AHK Vault - Unban HWID",
        "YesNo Iconi"
    )
    
    if (choice = "No")
        return

    try {
        AdminPost("/admin/unban-hwid", '{"hwid":"' hwid '"}')
        
        ; Send webhook
        details :=
    '{"name":"Action","value":"HWID Unban","inline":true},'
  . '{"name":"HWID","value":"' hwid '","inline":true},'
  . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("HWID Unbanned", details, 3066993)
        
        MsgBox "✅ Successfully unbanned HWID: " hwid, "AHK Vault - Admin", "Iconi"
        RefreshBannedHwidLabel(bannedHwidLabel)
    } catch as err {
        MsgBox "❌ Failed to unban HWID:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnAddAdminDiscord(editControl, adminLabel) {
    did := Trim(editControl.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }

    choice := MsgBox(
        "Add Admin:`n`n" did "`n`n"
        "This will grant full admin privileges.`n`n"
        "Continue?",
        "AHK Vault - Add Admin",
        "YesNo Iconi"
    )
    
    if (choice = "No")
        return

    try {
        AdminPost("/admin/add", '{"discord_id":"' did '"}')
        
        ; Send webhook
        details := '{"name":"Action","value":"Add Admin","inline":true},'
                 . '{"name":"Discord ID","value":"' did '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Admin Added", details, 5793266)
        
        MsgBox "✅ Successfully added admin: " did, "AHK Vault - Admin", "Iconi"
        RefreshAdminDiscordLabel(adminLabel)
    } catch as err {
        MsgBox "❌ Failed to add admin:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnRemoveAdminDiscord(editControl, adminLabel) {
    did := Trim(editControl.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }

    choice := MsgBox(
        "Remove Admin:`n`n" did "`n`n"
        "This will revoke admin privileges.`n`n"
        "Continue?",
        "AHK Vault - Remove Admin",
        "YesNo Icon?"
    )
    
    if (choice = "No")
        return

    try {
        AdminPost("/admin/remove", '{"discord_id":"' did '"}')
        
        ; Send webhook
        details := '{"name":"Action","value":"Remove Admin","inline":true},'
                 . '{"name":"Discord ID","value":"' did '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Admin Removed", details, 15158332)
        
        MsgBox "✅ Successfully removed admin: " did, "AHK Vault - Admin", "Iconi"
        RefreshAdminDiscordLabel(adminLabel)
    } catch as err {
        MsgBox "❌ Failed to remove admin:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnResetHwidBinding(editControl) {
    did := Trim(editControl.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }

    choice := MsgBox(
        "Reset HWID binding for Discord ID:`n`n" did "`n`n"
        "This will allow them to login from a new device.`n`n"
        "Continue?",
        "AHK Vault - Reset HWID Binding",
        "YesNo Iconi"
    )
    
    if (choice = "No")
        return

    try {
        AdminPost("/admin/reset-hwid-binding", '{"discord_id":"' did '"}')
        
        details := '{"name":"Action","value":"Reset HWID Binding","inline":true},'
                 . '{"name":"Discord ID","value":"' did '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("HWID Binding Reset", details, 15844367)
        
        MsgBox "✅ HWID binding reset for: " did "`n`nThey can now login from their current device.", "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to reset HWID binding:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

RefreshBannedFromServer(lblControl) {
    global WORKER_URL
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/manifest?t=" A_TickCount, false)
        req.Send()
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            bannedIds := []
            pos := 1
            while (pos := RegExMatch(resp, '"banned_discord_ids"\s*:\s*\[([^\]]+)\]', &m, pos)) {
                content := m[1]
                innerPos := 1
                while (innerPos := RegExMatch(content, '"([^"]+)"', &inner, innerPos)) {
                    bannedIds.Push(inner[1])
                    innerPos += StrLen(inner[0])
                }
                break
            }
            
            if (bannedIds.Length = 0) {
                lblControl.Value := "Banned Discord IDs: None"
            } else {
                lblControl.Value := "Banned Discord IDs (" bannedIds.Length "): " StrJoin(bannedIds, ", ")
            }
        }
    } catch {
        lblControl.Value := "Banned Discord IDs: Failed to load"
    }
}

RefreshBannedHwidLabel(lblControl) {
    global WORKER_URL
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/manifest?t=" A_TickCount, false)
        req.Send()
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            bannedHwids := []
            pos := 1
            while (pos := RegExMatch(resp, '"banned_hwids"\s*:\s*\[([^\]]+)\]', &m, pos)) {
                content := m[1]
                innerPos := 1
                while (innerPos := RegExMatch(content, '"([^"]+)"', &inner, innerPos)) {
                    bannedHwids.Push(inner[1])
                    innerPos += StrLen(inner[0])
                }
                break
            }
            
            if (bannedHwids.Length = 0) {
                lblControl.Value := "Banned HWIDs: None"
            } else {
                lblControl.Value := "Banned HWIDs (" bannedHwids.Length "): " StrJoin(bannedHwids, ", ")
            }
        }
    } catch {
        lblControl.Value := "Banned HWIDs: Failed to load"
    }
}

RefreshAdminDiscordLabel(lblControl) {
    global WORKER_URL
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/manifest?t=" A_TickCount, false)
        req.Send()
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            adminIds := []
            pos := 1
            while (pos := RegExMatch(resp, '"admin_discord_ids"\s*:\s*\[([^\]]+)\]', &m, pos)) {
                content := m[1]
                innerPos := 1
                while (innerPos := RegExMatch(content, '"([^"]+)"', &inner, innerPos)) {
                    adminIds.Push(inner[1])
                    innerPos += StrLen(inner[0])
                }
                break
            }
            
            if (adminIds.Length = 0) {
                lblControl.Value := "Admin Discord IDs: None"
            } else {
                lblControl.Value := "Admin Discord IDs (" adminIds.Length "): " StrJoin(adminIds, ", ")
            }
        }
    } catch {
        lblControl.Value := "Admin Discord IDs: Failed to load"
    }
}

; ========== CONTEXT MENU FOR LOGIN LOG ==========
ShowLogContextMenu(lv) {
    global COLORS
    
    ; Get selected row
    rowNum := lv.GetNext()
    if (rowNum = 0) {
        MsgBox "Please select a row first.", "No Selection", "Icon!"
        return
    }
    
    ; Get data from selected row
    username := lv.GetText(rowNum, 2)
    pcName := lv.GetText(rowNum, 3)
    discordId := lv.GetText(rowNum, 4)
    hwid := lv.GetText(rowNum, 6)
    
    if (discordId = "" || hwid = "") {
        MsgBox "Invalid row data.", "Error", "Icon!"
        return
    }
    
    ; Create context menu
    contextMenu := Menu()
    contextMenu.Add("🔒 Ban Discord ID", (*) => QuickBanDiscord(discordId))
    contextMenu.Add("🔒 Ban HWID", (*) => QuickBanHwid(hwid))
    contextMenu.Add("⚙️ Reset HWID Binding", (*) => QuickResetHwid(discordId))
    contextMenu.Add()
    contextMenu.Add("📋 Copy Discord ID", (*) => (A_Clipboard := discordId, ToolTip("Copied!"), SetTimer(() => ToolTip(), -2000)))
    contextMenu.Add("📋 Copy HWID", (*) => (A_Clipboard := hwid, ToolTip("Copied!"), SetTimer(() => ToolTip(), -2000)))
    contextMenu.Add("📋 Copy Username", (*) => (A_Clipboard := username, ToolTip("Copied!"), SetTimer(() => ToolTip(), -2000)))
    contextMenu.Add()
    contextMenu.Add("👤 View Profile", (*) => ViewUserProfileQuick(discordId))
    
    contextMenu.Show()
}

QuickBanDiscord(discordId) {
    choice := MsgBox("Ban Discord ID: " discordId "?", "Confirm Ban", "YesNo Icon!")
    if (choice = "No")
        return
    
    try {
        AdminPost("/admin/ban", '{"discord_id":"' discordId '"}')
        MsgBox "✅ Banned: " discordId, "Success", "Iconi T2"
        
        details := '{"name":"Action","value":"Quick Ban (Discord)","inline":true},'
                 . '{"name":"Discord ID","value":"' discordId '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("User Banned via Context Menu", details, 15158332)
    } catch as err {
        MsgBox "❌ Ban failed: " err.Message, "Error", "Icon!"
    }
}

QuickBanHwid(hwid) {
    choice := MsgBox("Ban HWID: " hwid "?", "Confirm Ban", "YesNo Icon!")
    if (choice = "No")
        return
    
    try {
        AdminPost("/admin/ban-hwid", '{"hwid":"' hwid '"}')
        MsgBox "✅ Banned HWID: " hwid, "Success", "Iconi T2"
        
        details :=
    '{"name":"Action","value":"Quick Ban (HWID)","inline":true},'
  . '{"name":"HWID","value":"' hwid '","inline":true},'
  . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'

        SendAdminActionWebhook("HWID Banned via Context Menu", details, 15158332)
    } catch as err {
        MsgBox "❌ Ban failed: " err.Message, "Error", "Icon!"
    }
}

QuickResetHwid(discordId) {
    choice := MsgBox("Reset HWID binding for: " discordId "?", "Confirm Reset", "YesNo Iconi")
    if (choice = "No")
        return
    
    try {
        AdminPost("/admin/reset-hwid-binding", '{"discord_id":"' discordId '"}')
        MsgBox "✅ HWID binding reset for: " discordId, "Success", "Iconi T2"
        
        details := '{"name":"Action","value":"Quick Reset HWID","inline":true},'
                 . '{"name":"Discord ID","value":"' discordId '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("HWID Reset via Context Menu", details, 15844367)
    } catch as err {
        MsgBox "❌ Reset failed: " err.Message, "Error", "Icon!"
    }
}

ViewUserProfileQuick(discordId) {
    global WORKER_URL
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/profile/" discordId, false)
        req.Send()
        
        if (req.Status = 404) {
            MsgBox "Profile not found for: " discordId, "Not Found"
            return
        }
        
        if (req.Status != 200) {
            MsgBox "Failed to load profile: HTTP " req.Status, "Error"
            return
        }
        
        resp := req.ResponseText
        
        username := JsonExtractAny(resp, "username")
        bio := JsonExtractAny(resp, "bio")
        totalMacros := JsonExtractAny(resp, "total_macros_run")
        
        MsgBox(
            "Discord ID: " discordId "`n`n"
            . "Username: " username "`n`n"
            . "Bio: " bio "`n`n"
            . "Total Macros Run: " totalMacros,
            "User Profile",
            "Iconi"
        )
        
    } catch as err {
        MsgBox "Error loading profile: " err.Message, "Error"
    }
}

; ========== LOGIN LOG FUNCTIONS ==========
LoadGlobalSessionLogIntoListView(lv, limit := 200) {
    global WORKER_URL, MASTER_KEY
    
    try {
        ToolTip "Loading login log..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("GET", WORKER_URL "/admin/logs?limit=" limit, false)
        req.SetRequestHeader("X-Master-Key", MASTER_KEY)
        req.Send()
        
        if (req.Status != 200) {
            ToolTip
            MsgBox "Failed to load logs: HTTP " req.Status, "Error"
            return
        }
        
        lv.Delete()
        
        resp := req.ResponseText
        pos := 1
        count := 0
        
        while (pos := RegExMatch(resp, '\{[^}]*"discord_id"[^}]*\}', &match, pos)) {
            logObj := match[0]
            
            time := ""
            username := ""
            pc := ""
            discordId := ""
            role := ""
            hwid := ""
            
            if RegExMatch(logObj, '"time"\s*:\s*"([^"]+)"', &m)
                time := m[1]
            if RegExMatch(logObj, '"user"\s*:\s*"([^"]+)"', &m)
                username := m[1]
            if RegExMatch(logObj, '"pc"\s*:\s*"([^"]+)"', &m)
                pc := m[1]
            if RegExMatch(logObj, '"discord_id"\s*:\s*"([^"]+)"', &m)
                discordId := m[1]
            if RegExMatch(logObj, '"role"\s*:\s*"([^"]+)"', &m)
                role := m[1]
            if RegExMatch(logObj, '"hwid"\s*:\s*"([^"]+)"', &m)
                hwid := m[1]
            
            lv.Add(, time, username, pc, discordId, role, hwid)
            
            count++
            pos += StrLen(match[0]) + match.Pos
        }
        
        lv.ModifyCol()
        ToolTip
        
    } catch as err {
        ToolTip
        MsgBox "Error loading logs: " err.Message, "Error"
    }
}

OnClearLog(lv) {
    choice := MsgBox(
        "Clear all login logs?`n`n"
        . "This will permanently delete all login history.`n`n"
        . "Continue?",
        "AHK Vault - Clear Logs",
        "YesNo Icon?"
    )
    
    if (choice = "No")
        return
    
    try {
        AdminPost("/admin/logs/clear", "{}")
        
        lv.Delete()
        
        details := '{"name":"Action","value":"Clear Login Logs","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Login Logs Cleared", details, 15158332)
        
        MsgBox "✅ Login logs cleared successfully!", "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to clear logs:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

; ========== SETTINGS FUNCTIONS ==========
OnSetGlobalPassword() {
    newPass := InputBox("Enter new global password:", "AHK Vault - Set Password", "W300 H120 Password").Value
    
    if (newPass = "")
        return
    
    confirmPass := InputBox("Confirm new password:", "AHK Vault - Confirm Password", "W300 H120 Password").Value
    
    if (newPass != confirmPass) {
        MsgBox "❌ Passwords do not match!", "AHK Vault - Admin", "Icon!"
        return
    }
    
    ; Hash the password (simple hash for demo - use better hashing in production)
    passwordHash := HashString(newPass)
    
    choice := MsgBox(
        "Set global password hash to:`n`n" passwordHash "`n`n"
        . "This will affect all users.`n`n"
        . "Continue?",
        "AHK Vault - Set Password",
        "YesNo Iconi"
    )
    
    if (choice = "No")
        return
    
    try {
        AdminPost("/admin/set-password", '{"password_hash":"' passwordHash '"}')
        
        details := '{"name":"Action","value":"Password Changed","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Global Password Updated", details, 15844367)
        
        MsgBox "✅ Password updated successfully!`n`nHash: " passwordHash, "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to set password:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnCopySnippet() {
    snippet := "global WORKER_URL := `"https://your-worker.workers.dev`"`n"
            . "global MASTER_KEY := `"your-master-key-here`"`n"
            . "global WEBHOOK_URL := `"your-webhook-url-here`"`n"
    
    A_Clipboard := snippet
    MsgBox "✅ Configuration snippet copied to clipboard!`n`nPaste this into your scripts.", "AHK Vault - Admin", "Iconi"
}

; ========== HELPER FUNCTIONS ==========
AdminPost(endpoint, bodyJson) {
    global WORKER_URL, MASTER_KEY
    
    url := WORKER_URL endpoint
    
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("POST", url, false)
    req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    req.SetRequestHeader("X-Master-Key", MASTER_KEY)
    req.Send(bodyJson)
    
    if (req.Status < 200 || req.Status >= 300)
        throw Error("Admin API error " req.Status ": " req.ResponseText)
    
    return req.ResponseText
}

GetHardwareId() {
    hwid := ""
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for proc in objWMI.ExecQuery("SELECT ProcessorId FROM Win32_Processor") {
            if (proc.ProcessorId != "" && proc.ProcessorId != "None") {
                hwid .= proc.ProcessorId
            }
            break
        }
    } catch {
    }
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for board in objWMI.ExecQuery("SELECT SerialNumber FROM Win32_BaseBoard") {
            if (board.SerialNumber != "" && board.SerialNumber != "None") {
                hwid .= board.SerialNumber
            }
            break
        }
    } catch {
    }
    
    if (hwid = "")
        hwid := A_ComputerName . A_UserName
    
    hash := 0
    loop parse hwid
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    
    return String(hash)
}

ReadDiscordId() {
    global SECURE_VAULT
    discordIdFile := SECURE_VAULT "\discord_id.txt"
    
    try {
        if FileExist(discordIdFile)
            return Trim(FileRead(discordIdFile, "UTF-8"))
    }
    return "Unknown"
}

FormatTimestampAdmin(timestamp) {
    try {
        if (timestamp = "" || timestamp = "0")
            return "Unknown"
        
        ; Convert milliseconds to seconds
        seconds := Integer(timestamp) / 1000
        
        ; Calculate difference from now
        nowSeconds := DateDiff(A_Now, "19700101000000", "Seconds")
        diff := nowSeconds - seconds
        
        if (diff < 3600)
            return Floor(diff / 60) "m ago"
        else if (diff < 86400)
            return Floor(diff / 3600) "h ago"
        else if (diff < 604800)
            return Floor(diff / 86400) "d ago"
        else
            return Floor(diff / 604800) "w ago"
    } catch {
        return "Recently"
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

JsonExtractAny(jsonStr, key) {
    if RegExMatch(jsonStr, '"' key '"\s*:\s*"([^"]*)"', &m)
        return m[1]
    if RegExMatch(jsonStr, '"' key '"\s*:\s*(\d+)', &m)
        return m[1]
    return ""
}

JsonExtractField(jsonStr, discordId, field) {
    ; Find the section for this discord_id
    pattern := '"discord_id"\s*:\s*"' discordId '"[^}]*"' field '"\s*:\s*("([^"]*)"|(\d+))'
    if RegExMatch(jsonStr, pattern, &m) {
        return (m[2] != "") ? m[2] : m[3]
    }
    return ""
}

StrJoin(arr, delimiter := ", ") {
    result := ""
    for index, value in arr {
        if (index > 1)
            result .= delimiter
        result .= value
    }
    return result
}

UrlEncode(str) {
    encoded := ""
    Loop Parse, str {
        char := A_LoopField
        code := Ord(char)
        
        if (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || InStr("-_.~", char)
            encoded .= char
        else
            encoded .= Format("%{:02X}", code)
    }
    return encoded
}