#Requires AutoHotkey v2.0
#SingleInstance Force

; ========== ADMIN TOOL - DO NOT DISTRIBUTE TO USERS ==========
; This file should ONLY be on your personal machine

global WORKER_URL := "https://empty-band-2be2.lewisjenkins558.workers.dev"
global WEBHOOK_URL := "https://discord.com/api/webhooks/1459209245294592070/EGWiUXTNSgUY1RrGwwCCLyM22S8Xln1PwPoj10wdqCY1YsPQCT38cLBGgkZcSccYX8r_"
global MASTER_KEY := "A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7A9fK3mQ2Z7"

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

; Send notification that admin tool was opened
SendAdminOpenNotification()

; Create the GUI
CreateAdminGui()

; ========== INITIALIZATION ==========
InitializeSecureVault() {
    global SECURE_VAULT, MACHINE_KEY
    
    MACHINE_KEY := GetOrCreatePersistentKey()
    dirHash := HashString(MACHINE_KEY . A_ComputerName)
    APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content\{" SubStr(dirHash, 1, 8) "}"
    SECURE_VAULT := APP_DIR "\{" SubStr(dirHash, 9, 8) "}"
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
               . '"footer":{"text":"AHK Vault Admin Tool"},'
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
    global WEBHOOK_URL
    
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

; ========== CREATE ADMIN GUI ==========
CreateAdminGui() {
    global COLORS
    
    myGui := Gui("+Resize", "AHK Vault - Admin Tool")
    myGui.BackColor := COLORS.bg
    myGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    ; Header
    myGui.Add("Text", "x0 y0 w900 h70 Background" COLORS.accent)
    myGui.Add("Text", "x20 y20 w860 h30 c" COLORS.text " BackgroundTrans", "🛡️ Admin Panel").SetFont("s18 bold")
    myGui.Add("Text", "x20 y50 w860 c" COLORS.text " BackgroundTrans", "Centralized Control Panel").SetFont("s9")
    
    ; ===== LOGIN LOG =====
    myGui.Add("Text", "x10 y85 w880 c" COLORS.textDim, "✅ Login Log (successful logins) - Right-click for options")
    lv := myGui.Add("ListView", "x10 y105 w880 h210 Background" COLORS.card " c" COLORS.text, 
        ["Time", "PC Name", "Discord ID", "Role", "HWID"])
    lv.ModifyCol(1, 140)
    lv.ModifyCol(2, 120)
    lv.ModifyCol(3, 120)
    lv.ModifyCol(4, 80)
    lv.ModifyCol(5, 120)
    
    ; Add context menu to ListView
    lv.OnEvent("ContextMenu", (*) => ShowLogContextMenu(lv, bannedLbl, bannedHwidLbl, adminLbl))
    
    myGui.Add("Text", "x10 y325 w880 h1 Background" COLORS.border)
    
    ; ===== DISCORD BAN =====
    myGui.Add("Text", "x10 y335 w880 c" COLORS.textDim, "🔒 Global Ban Management")
    
    myGui.Add("Text", "x10 y360 w120 c" COLORS.text, "Discord ID:")
    banEdit := myGui.Add("Edit", "x130 y356 w370 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    banBtn := myGui.Add("Button", "x520 y356 w110 h28 Background" COLORS.danger, "BAN")
    banBtn.SetFont("s9 bold")
    unbanBtn := myGui.Add("Button", "x640 y356 w110 h28 Background" COLORS.success, "UNBAN")
    unbanBtn.SetFont("s9 bold")
    
    bannedLbl := myGui.Add("Text", "x10 y390 w880 c" COLORS.textDim, "")
    RefreshBannedFromServer(bannedLbl)
    
    ; ===== HWID BAN =====
    myGui.Add("Text", "x10 y420 w120 c" COLORS.text, "HWID:")
    hwidEdit := myGui.Add("Edit", "x130 y416 w370 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    ; Initialize with current machine's HWID
    try {
        currentHwid := GetHardwareId()
        if (currentHwid != "")
            hwidEdit.Value := currentHwid
    } catch {
    }
    
    banHwidBtn := myGui.Add("Button", "x520 y416 w110 h28 Background" COLORS.danger, "BAN HWID")
    banHwidBtn.SetFont("s9 bold")
    unbanHwidBtn := myGui.Add("Button", "x640 y416 w110 h28 Background" COLORS.success, "UNBAN HWID")
    unbanHwidBtn.SetFont("s9 bold")
    
    bannedHwidLbl := myGui.Add("Text", "x10 y450 w880 c" COLORS.textDim, "")
    try RefreshBannedHwidLabel(bannedHwidLbl)
    
    myGui.Add("Text", "x10 y480 w880 h1 Background" COLORS.border)
    
    ; ===== LOCAL BAN/UNBAN =====
    myGui.Add("Text", "x10 y490 w880 c" COLORS.textDim, "💻 Local Machine Controls")
    
    currentDiscordId := ReadDiscordId()
    currentHwid := GetHardwareId()
    
    myGui.Add("Text", "x10 y515 w120 c" COLORS.text, "This Machine:")
    myGui.Add("Text", "x130 y515 w370 c" COLORS.textDim, "Discord: " currentDiscordId " | HWID: " currentHwid)
    
    banLocalBtn := myGui.Add("Button", "x520 y511 w110 h28 Background" COLORS.danger, "BAN LOCAL")
    banLocalBtn.SetFont("s9 bold")
    unbanLocalBtn := myGui.Add("Button", "x640 y511 w110 h28 Background" COLORS.success, "UNBAN LOCAL")
    unbanLocalBtn.SetFont("s9 bold")
    
    myGui.Add("Text", "x10 y545 w880 h1 Background" COLORS.border)
    
    ; ===== ADMIN IDS =====
    myGui.Add("Text", "x10 y555 w880 c" COLORS.textDim, "🛡️ Admin Discord IDs")
    
    myGui.Add("Text", "x10 y580 w120 c" COLORS.text, "Admin ID:")
    adminEdit := myGui.Add("Edit", "x130 y576 w370 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    addAdminBtn := myGui.Add("Button", "x520 y576 w110 h28 Background" COLORS.accentAlt, "Add Admin")
    addAdminBtn.SetFont("s9 bold")
    delAdminBtn := myGui.Add("Button", "x640 y576 w110 h28 Background" COLORS.danger, "Remove")
    delAdminBtn.SetFont("s9 bold")
    
    adminLbl := myGui.Add("Text", "x10 y610 w880 c" COLORS.textDim, "")
    RefreshAdminDiscordLabel(adminLbl)
    
    myGui.Add("Text", "x10 y640 w880 h1 Background" COLORS.border)
    
    ; ===== BUTTONS =====
    refreshBtn := myGui.Add("Button", "x10 y655 w130 h34 Background" COLORS.card, "🔄 Refresh Log")
    refreshBtn.SetFont("s10")
    clearLogBtn := myGui.Add("Button", "x150 y655 w130 h34 Background" COLORS.card, "🗑️ Clear Log")
    clearLogBtn.SetFont("s10")
    setPassBtn := myGui.Add("Button", "x290 y655 w190 h34 Background" COLORS.accentAlt, "🔐 Set Global Password")
    setPassBtn.SetFont("s10")
    copySnippetBtn := myGui.Add("Button", "x490 y655 w190 h34 Background" COLORS.card, "📋 Copy Manifest Snippet")
    copySnippetBtn.SetFont("s10")
    exitBtn := myGui.Add("Button", "x690 y655 w200 h34 Background" COLORS.danger, "❌ Exit Admin Tool")
    exitBtn.SetFont("s10 bold")
    
    resetHwidBtn := myGui.Add("Button", "x755 y25 w90 h35 Background" COLORS.warning, "Reset HWID")
    resetHwidBtn.SetFont("s9")
    resetHwidBtn.OnEvent("Click", (*) => OnResetHwid())
    myGui.Add("Text", "x10 y680 w880 h1 Background" COLORS.border)

    myGui.Add("Text", "x10 y690 w880 c" COLORS.textDim, "⚙️ System Maintenance")

    myGui.Add("Text", "x10 y715 w120 c" COLORS.text, "Discord ID:")
    resetHwidEdit := myGui.Add("Edit", "x130 y711 w370 h28 Background" COLORS.bgLight " c" COLORS.text)

    resetHwidBtn := myGui.Add("Button", "x520 y711 w110 h28 Background" COLORS.warning, "Reset HWID")
    resetHwidBtn.SetFont("s9 bold")
    resetHwidBtn.OnEvent("Click", (*) => OnResetHwidBinding(resetHwidEdit))

    ; ===== EVENTS =====
    banBtn.OnEvent("Click", (*) => OnBanDiscordId(banEdit, bannedLbl))
    unbanBtn.OnEvent("Click", (*) => OnUnbanDiscordId(banEdit, bannedLbl))
    
    banHwidBtn.OnEvent("Click", (*) => OnBanHwid(hwidEdit, bannedHwidLbl))
    unbanHwidBtn.OnEvent("Click", (*) => OnUnbanHwid(hwidEdit, bannedHwidLbl))
    
    banLocalBtn.OnEvent("Click", (*) => OnBanLocal(bannedLbl, bannedHwidLbl))
    unbanLocalBtn.OnEvent("Click", (*) => OnUnbanLocal(bannedLbl, bannedHwidLbl))
    
    addAdminBtn.OnEvent("Click", (*) => OnAddAdminDiscord(adminEdit, adminLbl))
    delAdminBtn.OnEvent("Click", (*) => OnRemoveAdminDiscord(adminEdit, adminLbl))
    
    refreshBtn.OnEvent("Click", (*) => LoadGlobalSessionLogIntoListView(lv, 200))
    clearLogBtn.OnEvent("Click", (*) => OnClearLog(lv))
    setPassBtn.OnEvent("Click", (*) => OnSetGlobalPassword())
    copySnippetBtn.OnEvent("Click", (*) => OnCopySnippet())
    exitBtn.OnEvent("Click", (*) => ExitApp())
    
    myGui.OnEvent("Close", (*) => ExitApp())
    myGui.Show("w900 h750 Center")
    
    ; Load logs on startup
    LoadGlobalSessionLogIntoListView(lv, 200)
}

OnResetHwid() {
    did := InputBox("Enter Discord ID to reset HWID binding:", "Reset HWID").Value
    if (did = "")
        return
    
    try {
        AdminPost("/admin/reset-hwid", '{"discord_id":"' did '"}')
        MsgBox "✅ HWID binding reset for: " did, "Success", "Iconi"
    } catch as err {
        MsgBox "❌ Failed: " err.Message, "Error", "Icon!"
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

; ========== CONTEXT MENU FOR LOGIN LOG ==========
ShowLogContextMenu(lv, bannedLbl, bannedHwidLbl, adminLbl) {
    global COLORS
    
    ; Get selected row
    rowNum := lv.GetNext()
    if (rowNum = 0) {
        MsgBox "Please select a row first.", "No Selection", "Icon!"
        return
    }
    
    ; Get data from selected row
    discordId := lv.GetText(rowNum, 3)
    hwid := lv.GetText(rowNum, 5)
    pcName := lv.GetText(rowNum, 2)
    
    if (discordId = "" || hwid = "") {
        MsgBox "Invalid row data.", "Error", "Icon!"
        return
    }
    
    ; Create context menu
    contextMenu := Menu()
    contextMenu.Add("🚫 Ban Discord ID: " discordId, (*) => ContextBanDiscord(discordId, bannedLbl))
    contextMenu.Add("🚫 Ban HWID: " hwid, (*) => ContextBanHwid(hwid, bannedHwidLbl))
    contextMenu.Add("🚫 Ban Both (Discord + HWID)", (*) => ContextBanBoth(discordId, hwid, bannedLbl, bannedHwidLbl))
    contextMenu.Add()  ; Separator
    contextMenu.Add("✅ Unban Discord ID", (*) => ContextUnbanDiscord(discordId, bannedLbl))
    contextMenu.Add("✅ Unban HWID", (*) => ContextUnbanHwid(hwid, bannedHwidLbl))
    contextMenu.Add("✅ Unban Both", (*) => ContextUnbanBoth(discordId, hwid, bannedLbl, bannedHwidLbl))
    contextMenu.Add()  ; Separator
    contextMenu.Add("🛡️ Make Admin", (*) => ContextMakeAdmin(discordId, adminLbl))
    contextMenu.Add("❌ Remove Admin", (*) => ContextRemoveAdmin(discordId, adminLbl))
    contextMenu.Add()  ; Separator
    contextMenu.Add("🗑️ Remove from Log", (*) => ContextRemoveFromLog(lv, rowNum))
    contextMenu.Add("📋 Copy Discord ID", (*) => (A_Clipboard := discordId, ToolTip("Copied: " discordId), SetTimer(() => ToolTip(), -2000)))
    contextMenu.Add("📋 Copy HWID", (*) => (A_Clipboard := hwid, ToolTip("Copied: " hwid), SetTimer(() => ToolTip(), -2000)))
    
    contextMenu.Show()
}

; Context menu actions
ContextBanDiscord(discordId, bannedLbl) {
    try {
        AdminPost("/admin/ban", '{"discord_id":"' discordId '"}')
        Sleep 2000
        RefreshBannedFromServer(bannedLbl)
        
        details := '{"name":"Action","value":"Ban User (Context Menu)","inline":true},'
                 . '{"name":"Discord ID","value":"' discordId '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("User Banned", details, 15158332)
        
        ToolTip "✅ Banned Discord ID: " discordId
        SetTimer () => ToolTip(), -3000
    } catch as err {
        MsgBox "❌ Failed to ban:`n" err.Message, "Error", "Icon!"
    }
}

ContextBanHwid(hwid, bannedHwidLbl) {
    try {
        AdminPost("/admin/ban-hwid", '{"hwid":"' hwid '"}')
        Sleep 2000
        RefreshBannedHwidLabel(bannedHwidLbl)
        
        details := '{"name":"Action","value":"Ban HWID (Context Menu)","inline":true},'
                 . '{"name":"HWID","value":"' hwid '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("HWID Banned", details, 15158332)
        
        ToolTip "✅ Banned HWID: " hwid
        SetTimer () => ToolTip(), -3000
    } catch as err {
        MsgBox "❌ Failed to ban HWID:`n" err.Message, "Error", "Icon!"
    }
}

ContextBanBoth(discordId, hwid, bannedLbl, bannedHwidLbl) {
    try {
        AdminPost("/admin/ban", '{"discord_id":"' discordId '"}')
        Sleep 1000
        AdminPost("/admin/ban-hwid", '{"hwid":"' hwid '"}')
        Sleep 2000
        
        RefreshBannedFromServer(bannedLbl)
        RefreshBannedHwidLabel(bannedHwidLbl)
        
        details := '{"name":"Action","value":"Ban Both (Context Menu)","inline":true},'
                 . '{"name":"Discord ID","value":"' discordId '","inline":true},'
                 . '{"name":"HWID","value":"' hwid '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("User & HWID Banned", details, 15158332)
        
        ToolTip "✅ Banned both Discord ID and HWID"
        SetTimer () => ToolTip(), -3000
    } catch as err {
        MsgBox "❌ Failed to ban:`n" err.Message, "Error", "Icon!"
    }
}

ContextUnbanDiscord(discordId, bannedLbl) {
    try {
        AdminPost("/admin/unban", '{"discord_id":"' discordId '"}')
        Sleep 2000
        RefreshBannedFromServer(bannedLbl)
        
        details := '{"name":"Action","value":"Unban User (Context Menu)","inline":true},'
                 . '{"name":"Discord ID","value":"' discordId '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("User Unbanned", details, 3066993)
        
        ToolTip "✅ Unbanned Discord ID: " discordId
        SetTimer () => ToolTip(), -3000
    } catch as err {
        MsgBox "❌ Failed to unban:`n" err.Message, "Error", "Icon!"
    }
}

ContextUnbanHwid(hwid, bannedHwidLbl) {
    try {
        AdminPost("/admin/unban-hwid", '{"hwid":"' hwid '"}')
        Sleep 2000
        RefreshBannedHwidLabel(bannedHwidLbl)
        
        details := '{"name":"Action","value":"Unban HWID (Context Menu)","inline":true},'
                 . '{"name":"HWID","value":"' hwid '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("HWID Unbanned", details, 15844367)
        
        ToolTip "✅ Unbanned HWID: " hwid
        SetTimer () => ToolTip(), -3000
    } catch as err {
        MsgBox "❌ Failed to unban HWID:`n" err.Message, "Error", "Icon!"
    }
}

ContextUnbanBoth(discordId, hwid, bannedLbl, bannedHwidLbl) {
    try {
        AdminPost("/admin/unban", '{"discord_id":"' discordId '"}')
        Sleep 1000
        AdminPost("/admin/unban-hwid", '{"hwid":"' hwid '"}')
        Sleep 2000
        
        RefreshBannedFromServer(bannedLbl)
        RefreshBannedHwidLabel(bannedHwidLbl)
        
        details := '{"name":"Action","value":"Unban Both (Context Menu)","inline":true},'
                 . '{"name":"Discord ID","value":"' discordId '","inline":true},'
                 . '{"name":"HWID","value":"' hwid '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("User & HWID Unbanned", details, 3066993)
        
        ToolTip "✅ Unbanned both Discord ID and HWID"
        SetTimer () => ToolTip(), -3000
    } catch as err {
        MsgBox "❌ Failed to unban:`n" err.Message, "Error", "Icon!"
    }
}

ContextMakeAdmin(discordId, adminLbl) {
    try {
        AdminPost("/admin/add", '{"discord_id":"' discordId '"}')
        Sleep 1000
        RefreshAdminDiscordLabel(adminLbl)
        
        details := '{"name":"Action","value":"Add Admin (Context Menu)","inline":true},'
                 . '{"name":"Discord ID","value":"' discordId '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Admin Added", details, 3066993)
        
        ToolTip "✅ Made admin: " discordId
        SetTimer () => ToolTip(), -3000
    } catch as err {
        MsgBox "❌ Failed to add admin:`n" err.Message, "Error", "Icon!"
    }
}

ContextRemoveAdmin(discordId, adminLbl) {
    try {
        AdminPost("/admin/remove", '{"discord_id":"' discordId '"}')
        Sleep 1000
        RefreshAdminDiscordLabel(adminLbl)
        
        details := '{"name":"Action","value":"Remove Admin (Context Menu)","inline":true},'
                 . '{"name":"Discord ID","value":"' discordId '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Admin Removed", details, 15158332)
        
        ToolTip "✅ Removed admin: " discordId
        SetTimer () => ToolTip(), -3000
    } catch as err {
        MsgBox "❌ Failed to remove admin:`n" err.Message, "Error", "Icon!"
    }
}

ContextRemoveFromLog(lv, rowNum) {
    choice := MsgBox("Remove this entry from the log?`n`nThis only removes it from the display, not from the server.", "Confirm", "YesNo Icon?")
    if (choice = "No")
        return
    
    lv.Delete(rowNum)
    ToolTip "✅ Removed from display"
    SetTimer () => ToolTip(), -2000
}

; ========== LOCAL BAN/UNBAN FUNCTIONS ==========
OnBanLocal(bannedLbl, bannedHwidLbl) {
    currentDiscordId := ReadDiscordId()
    currentHwid := GetHardwareId()
    
    choice := MsgBox(
        "⚠️ WARNING ⚠️`n`n"
        . "This will BAN your local machine:`n`n"
        . "Discord ID: " currentDiscordId "`n"
        . "HWID: " currentHwid "`n`n"
        . "Are you sure?",
        "AHK Vault - Ban Local Machine",
        "YesNo Icon! Default2"
    )
    
    if (choice = "No")
        return
    
    try {
        ; Ban Discord ID
        AdminPost("/admin/ban", '{"discord_id":"' currentDiscordId '"}')
        Sleep 1000
        
        ; Ban HWID
        AdminPost("/admin/ban-hwid", '{"hwid":"' currentHwid '"}')
        Sleep 2000
        
        RefreshBannedFromServer(bannedLbl)
        RefreshBannedHwidLabel(bannedHwidLbl)
        
        ; Send webhook notification
        details := '{"name":"Action","value":"Ban Local Machine","inline":true},'
                 . '{"name":"Discord ID","value":"' currentDiscordId '","inline":true},'
                 . '{"name":"HWID","value":"' currentHwid '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Local Machine Banned", details, 15158332)
        
        MsgBox(
            "✅ Local machine has been BANNED globally:`n`n"
            . "Discord ID: " currentDiscordId "`n"
            . "HWID: " currentHwid "`n`n"
            . "This machine will no longer be able to login.",
            "AHK Vault - Admin",
            "Iconi"
        )
    } catch as err {
        MsgBox "❌ Failed to ban local machine:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnUnbanLocal(bannedLbl, bannedHwidLbl) {
    currentDiscordId := ReadDiscordId()
    currentHwid := GetHardwareId()
    
    choice := MsgBox(
        "Unban your local machine?`n`n"
        . "Discord ID: " currentDiscordId "`n"
        . "HWID: " currentHwid,
        "AHK Vault - Unban Local Machine",
        "YesNo Iconi"
    )
    
    if (choice = "No")
        return
    
    try {
        ; Unban Discord ID
        AdminPost("/admin/unban", '{"discord_id":"' currentDiscordId '"}')
        Sleep 1000
        
        ; Unban HWID
        AdminPost("/admin/unban-hwid", '{"hwid":"' currentHwid '"}')
        Sleep 2000
        
        RefreshBannedFromServer(bannedLbl)
        RefreshBannedHwidLabel(bannedHwidLbl)
        
        ; Send webhook notification
        details := '{"name":"Action","value":"Unban Local Machine","inline":true},'
                 . '{"name":"Discord ID","value":"' currentDiscordId '","inline":true},'
                 . '{"name":"HWID","value":"' currentHwid '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Local Machine Unbanned", details, 3066993)
        
        MsgBox(
            "✅ Local machine has been UNBANNED globally:`n`n"
            . "Discord ID: " currentDiscordId "`n"
            . "HWID: " currentHwid "`n`n"
            . "This machine can now login again.",
            "AHK Vault - Admin",
            "Iconi"
        )
    } catch as err {
        MsgBox "❌ Failed to unban local machine:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
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

; ========== ADMIN API CALLS ==========
AdminPost(endpoint, body) {
    global WORKER_URL, MASTER_KEY
    
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("POST", WORKER_URL "/" LTrim(endpoint, "/"), false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("User-Agent", "AHK-Vault-Admin")
    
    ; Send master key if available
    if (MASTER_KEY != "")
        req.SetRequestHeader("X-Master-Key", MASTER_KEY)
    
    req.Send(body)
    
    if (req.Status < 200 || req.Status >= 300) {
        throw Error("Admin API error: " req.Status)
    }
    
    return req.ResponseText
}

AdminGet(endpoint) {
    global WORKER_URL, MASTER_KEY
    
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("GET", WORKER_URL "/" LTrim(endpoint, "/"), false)
    req.SetRequestHeader("User-Agent", "AHK-Vault-Admin")
    
    ; Send master key if available
    if (MASTER_KEY != "")
        req.SetRequestHeader("X-Master-Key", MASTER_KEY)
    
    req.Send()
    
    if (req.Status < 200 || req.Status >= 300) {
        throw Error("Admin API error: " req.Status)
    }
    
    return req.ResponseText
}

; ========== BAN MANAGEMENT ==========
OnBanDiscordId(banEdit, bannedLbl) {
    did := Trim(banEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }

    try {
        AdminPost("/admin/ban", '{"discord_id":"' did '"}')
        Sleep 2000
        RefreshBannedFromServer(bannedLbl)
        
        ; Send webhook notification
        details := '{"name":"Action","value":"Ban User","inline":true},'
                 . '{"name":"Discord ID","value":"' did '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("User Banned", details, 15158332)
        
        MsgBox "✅ Globally BANNED: " did, "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to ban globally:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnUnbanDiscordId(banEdit, bannedLbl) {
    did := Trim(banEdit.Value)
    did := RegExReplace(did, "[^\d]", "")

    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }

    try {
        AdminPost("/admin/unban", '{"discord_id":"' did '"}')
        Sleep 2000
        RefreshBannedFromServer(bannedLbl)
        
        ; Send webhook
        details := '{"name":"Action","value":"Unban User","inline":true},'
                 . '{"name":"Discord ID","value":"' did '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("User Unbanned", details, 3066993)
        
        MsgBox "✅ Globally UNBANNED: " did "`n`nNote: Changes may take a few seconds to propagate.", "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to unban globally:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnBanHwid(hwidEdit, bannedHwidLbl) {
    hwid := Trim(hwidEdit.Value)
    hwid := RegExReplace(hwid, "[^\d]", "")
    
    if (hwid = "") {
        MsgBox "Enter a valid HWID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }
    
    try {
        body := '{"hwid":"' JsonEscape(hwid) '"}'
        AdminPost("/admin/ban-hwid", body)
        Sleep 2000
        RefreshBannedHwidLabel(bannedHwidLbl)
        
        ; Send webhook
        details := '{"name":"Action","value":"Ban HWID","inline":true},'
                 . '{"name":"HWID","value":"' hwid '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("HWID Banned", details, 15158332)
        
        MsgBox "✅ Globally BANNED HWID: " hwid, "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to ban HWID globally:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnUnbanHwid(hwidEdit, bannedHwidLbl) {
    hwid := Trim(hwidEdit.Value)
    hwid := RegExReplace(hwid, "[^\d]", "")
    
    if (hwid = "") {
        MsgBox "Enter a valid HWID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }
    
    try {
        body := '{"hwid":"' JsonEscape(hwid) '"}'
        AdminPost("/admin/unban-hwid", body)
        Sleep 2000
        RefreshBannedHwidLabel(bannedHwidLbl)
        
        ; Send webhook
        details := '{"name":"Action","value":"Unban HWID","inline":true},'
                 . '{"name":"HWID","value":"' hwid '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("HWID Unbanned", details, 15844367)
        
        MsgBox "✅ Globally UNBANNED HWID: " hwid, "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to unban HWID globally:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnAddAdminDiscord(adminEdit, adminLbl) {
    did := Trim(adminEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }

    try {
        AdminPost("/admin/add", '{"discord_id":"' did '"}')
        Sleep 1000
        RefreshAdminDiscordLabel(adminLbl)
        
        ; Send webhook
        details := '{"name":"Action","value":"Add Admin","inline":true},'
                 . '{"name":"Discord ID","value":"' did '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Admin Added", details, 3066993)
        
        MsgBox "✅ Globally added admin: " did, "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to add admin globally:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

OnRemoveAdminDiscord(adminEdit, adminLbl) {
    did := Trim(adminEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "AHK Vault - Admin", "Icon!"
        return
    }

    try {
        AdminPost("/admin/remove", '{"discord_id":"' did '"}')
        Sleep 1000
        RefreshAdminDiscordLabel(adminLbl)
        
        ; Send webhook
        details := '{"name":"Action","value":"Remove Admin","inline":true},'
                 . '{"name":"Discord ID","value":"' did '","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Admin Removed", details, 15158332)
        
        MsgBox "✅ Globally removed admin: " did, "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to remove admin globally:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

; ========== PASSWORD MANAGEMENT ==========
OnSetGlobalPassword() {
    pw := InputBox("Enter NEW universal password (this pushes to global manifest).", "AHK Vault - Set Global Password", "Password w560 h190")
    if (pw.Result != "OK")
        return

    newPass := Trim(pw.Value)
    if (newPass = "") {
        MsgBox "Password cannot be blank.", "AHK Vault - Invalid", "Icon! 0x30"
        return
    }

    h := HashPassword(newPass)
    body := '{"password_hash":"' h '"}'

    try {
        AdminPost("/admin/set-password", body)
        
        ; Send webhook
        details := '{"name":"Action","value":"Global Password Changed","inline":true},'
                 . '{"name":"New Hash","value":"' SubStr(h, 1, 20) '...","inline":false},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Security Update", details, 15105570)
        
        MsgBox "✅ Global password updated in manifest.`n`nNew password_hash: " h, "AHK Vault", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to set global password:`n" err.Message, "AHK Vault", "Icon! 0x10"
    }
}

OnCopySnippet() {
    pw := InputBox(
        "Enter the NEW universal password.`n`nThis will copy password_hash for manifest.json.",
        "AHK Vault - Generate manifest snippet",
        "Password w560 h190"
    )
    if (pw.Result != "OK")
        return

    newPass := Trim(pw.Value)
    if (newPass = "") {
        MsgBox "Password cannot be blank.", "AHK Vault - Invalid", "Icon! 0x30"
        return
    }

    h := HashPassword(newPass)
    snippet := '"password_hash": "' h '"'
    A_Clipboard := snippet

    MsgBox "✅ Copied to clipboard.`n`nPaste into manifest.json:`n`n" snippet, "AHK Vault", "Iconi"
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

; ========== LOG MANAGEMENT ==========
OnClearLog(lv) {
    choice := MsgBox("Are you sure you want to clear all login logs?", "Confirm", "YesNo Icon?")
    if (choice = "No")
        return
    
    try {
        AdminPost("/admin/logs/clear", "{}")
        lv.Delete()
        
        ; Send webhook
        details := '{"name":"Action","value":"Login Logs Cleared","inline":true},'
                 . '{"name":"Admin","value":"' A_UserName '@' A_ComputerName '","inline":true}'
        SendAdminActionWebhook("Logs Cleared", details, 15844367)
        
        MsgBox "✅ Global login log cleared.", "AHK Vault - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Clear failed:`n" err.Message, "AHK Vault - Admin", "Icon!"
    }
}

LoadGlobalSessionLogIntoListView(lv, limit := 200) {
    global WORKER_URL
    lv.Delete()

    resp := ""
    try {
        ; Use AdminGet instead of direct request
        resp := AdminGet("/admin/logs?limit=" limit)
    } catch as err {
        MsgBox "❌ Failed to load logs:`n" err.Message, "AHK Vault - Admin", "Icon!"
        return
    }

    if !RegExMatch(resp, '(?s)"logs"\s*:\s*\[(.*)\]\s*}', &m)
        return

    logsBlock := m[1]
    pos := 1
    
    ; Track unique entries: "discordId|hwid" as key
    seen := Map()

    while (p := RegExMatch(logsBlock, '(?s)\{.*?\}', &mm, pos)) {
        one := mm[0]
        pos := p + StrLen(one)

        t    := JsonExtractAny(one, "time")
        pc   := JsonExtractAny(one, "pc")
        did  := JsonExtractAny(one, "discord_id")
        role := JsonExtractAny(one, "role")
        hwid := JsonExtractAny(one, "hwid")
        
        ; Create unique key from discord ID and HWID
        uniqueKey := did "|" hwid
        
        ; Skip if we've already seen this combination
        if seen.Has(uniqueKey)
            continue
        
        seen[uniqueKey] := true
        lv.Add("", t, pc, did, role, hwid)
    }
    
    ; Auto-size columns to fit content
    Loop 5
        lv.ModifyCol(A_Index, "AutoHdr")
}

JsonExtractAny(json, key) {
    ; Handles "key":"value" OR "key":123 OR "key":true
    pat1 := '(?s)"' key '"\s*:\s*"((?:\\.|[^"\\])*)"'
    if RegExMatch(json, pat1, &m1) {
        v := m1[1]
        v := StrReplace(v, '\"', '"')
        v := StrReplace(v, "\\n", "`n")
        v := StrReplace(v, "\\r", "`r")
        v := StrReplace(v, "\\t", "`t")
        v := StrReplace(v, "\\", "\")
        return v
    }

    pat2 := '(?s)"' key '"\s*:\s*([^,\}\]]+)'
    if RegExMatch(json, pat2, &m2) {
        return Trim(m2[1], " `t`r`n")
    }

    return ""
}

; ========== REFRESH LABELS ==========
RefreshBannedFromServer(lblCtrl) {
    global WORKER_URL
    
    try {
        ; Get manifest through worker
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/manifest", false)
        req.Send()
        
        if (req.Status != 200) {
            lblCtrl.Value := "Banned Discord IDs: (failed to sync)"
            return false
        }
        
        resp := req.ResponseText
        
        ; Extract banned list from GitHub manifest
        bannedIds := []
        if RegExMatch(resp, '(?s)"banned_discord_ids"\s*:\s*\[(.*?)\]', &m) {
            inner := m[1]
            pos := 1
            while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem, pos)) {
                bannedIds.Push(mItem[1])
                pos += StrLen(mItem[0])
            }
        }
        
        if (bannedIds.Length = 0) {
            lblCtrl.Value := "Banned Discord IDs: (none)"
            return true
        }
        
        s := "Banned Discord IDs: "
        for id in bannedIds
            s .= id ", "
        lblCtrl.Value := RTrim(s, ", ")
        
        return true
    } catch as err {
        lblCtrl.Value := "Banned Discord IDs: (sync error: " err.Message ")"
        return false
    }
}

RefreshBannedHwidLabel(lblCtrl) {
    global WORKER_URL
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/manifest", false)
        req.Send()
        
        if (req.Status != 200) {
            lblCtrl.Value := "Banned HWIDs: (failed to sync)"
            return false
        }
        
        resp := req.ResponseText
        
        bannedHwids := []
        if RegExMatch(resp, '(?s)"banned_hwids"\s*:\s*\[(.*?)\]', &m) {
            inner := m[1]
            pos := 1
            while (pos := RegExMatch(inner, '"([^"]+)"', &mItem, pos)) {
                v := Trim(mItem[1])
                if (v != "")
                    bannedHwids.Push(v)
                pos += StrLen(mItem[0])
            }
        }
        
        if (bannedHwids.Length = 0) {
            lblCtrl.Value := "Banned HWIDs: (none)"
            return true
        }
        
        s := "Banned HWIDs: "
        for id in bannedHwids
            s .= id ", "
        lblCtrl.Value := RTrim(s, ", ")
        
        return true
    } catch as err {
        lblCtrl.Value := "Banned HWIDs: (sync error)"
        return false
    }
}

RefreshAdminDiscordLabel(adminLbl) {
    global WORKER_URL
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/manifest", false)
        req.Send()
        
        if (req.Status != 200) {
            adminLbl.Value := "Admin Discord IDs: (failed to sync)"
            return false
        }
        
        resp := req.ResponseText
        
        adminIds := []
        if RegExMatch(resp, '(?s)"admin_discord_ids"\s*:\s*\[(.*?)\]', &m) {
            inner := m[1]
            pos := 1
            while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem, pos)) {
                adminIds.Push(mItem[1])
                pos += StrLen(mItem[0])
            }
        }
        
        if (adminIds.Length = 0) {
            adminLbl.Value := "Admin Discord IDs: (none)"
            return true
        }
        
        s := "Admin Discord IDs: "
        for id in adminIds
            s .= id ", "
        adminLbl.Value := RTrim(s, ", ")
        
        return true
    } catch as err {
        adminLbl.Value := "Admin Discord IDs: (sync error)"
        return false
    }
}

; ========== HELPER FUNCTIONS ==========
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

    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for bios in objWMI.ExecQuery("SELECT SerialNumber FROM Win32_BIOS") {
            if (bios.SerialNumber != "" && bios.SerialNumber != "None") {
                hwid .= bios.SerialNumber
            }
            break
        }
    } catch {
    }

    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for disk in objWMI.ExecQuery("SELECT VolumeSerialNumber FROM Win32_LogicalDisk WHERE DeviceID='C:'") {
            if (disk.VolumeSerialNumber != "" && disk.VolumeSerialNumber != "None") {
                hwid .= disk.VolumeSerialNumber
            }
            break
        }
    } catch {
    }

    if (hwid = "") {
        hwid := A_ComputerName . A_UserName
    }

    hash := 0
    loop parse hwid {
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    }

    return String(hash)
}

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}