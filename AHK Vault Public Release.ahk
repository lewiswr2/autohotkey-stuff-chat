#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

global LAUNCHER_VERSION := "1.0.0"


; ================= AUTHENTICATION GLOBALS =================
global WORKER_URL := "https://empty-band-2be2.lewisjenkins558.workers.dev"
global DISCORD_URL := "https://discord.gg/PQ85S32Ht8"

; Credential & Session Files
global CRED_FILE := ""
global SESSION_FILE := ""
global DISCORD_ID_FILE := ""
global DISCORD_BAN_FILE := ""
global ADMIN_DISCORD_FILE := ""
global SESSION_LOG_FILE := ""
global MACHINE_BAN_FILE := ""
global HWID_BINDING_FILE := ""
global LAST_CRED_HASH_FILE := ""
global HWID_BAN_FILE := ""

; Master Credentials
global MASTER_KEY := ""
global DISCORD_WEBHOOK := ""
global ADMIN_PASS := ""
global SECURE_CONFIG_FILE := ""
global ENCRYPTED_KEY_FILE := ""
global MASTER_KEY_ROTATION_FILE := ""

; Login Settings
global DEFAULT_USER := "AHKvaultmacros@discord"
global MASTER_USER := "master"
global MAX_ATTEMPTS := 10
global LOCKOUT_FILE := A_Temp "\.lockout"

; Auth State
global gLoginGui := 0
global KEY_HISTORY := []
global APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content"
global SECURE_VAULT := APP_DIR "\{" CreateGUID() "}"
global BASE_DIR := SECURE_VAULT "\data"
global VERSION_FILE := SECURE_VAULT "\ver"
global ICON_DIR := SECURE_VAULT "\res"
global MANIFEST_URL := DecryptManifestUrl()
global mainGui := 0
global MACHINE_KEY := ""

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

#HotIf
^!p:: AdminPanel()
^!l::LogoutNow()

#HotIf
; =========================================
InitializeSecureVault()
SetTaskbarIcon()

did := ReadDiscordId()
isBanned := IsDiscordBanned()
isMachineBan := IsMachineBanned()
serverBan := CheckServerBanStatus()
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
    CheckForUpdatesPrompt()
    CreateMainGui()
    return
}

CreateLoginGui()
return

; ================= UTILITY FUNCTIONS =================

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

NoCacheUrl(url) {
    sep := InStr(url, "?") ? "&" : "?"
    return url sep "t=" A_TickCount
}

; ============= SECURITY FUNCTIONS =============
InitializeSecureVault() {
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR, VERSION_FILE, MACHINE_KEY
    global CRED_FILE, SESSION_FILE, DISCORD_ID_FILE, DISCORD_BAN_FILE
    global ADMIN_DISCORD_FILE, SESSION_LOG_FILE, MACHINE_BAN_FILE
    global HWID_BINDING_FILE, LAST_CRED_HASH_FILE, SECURE_CONFIG_FILE
    global ENCRYPTED_KEY_FILE, MASTER_KEY_ROTATION_FILE
    HWID_BAN_FILE := SECURE_VAULT "\banned_hwids.txt"

    ; Use PERSISTENT machine key stored in registry
    MACHINE_KEY := GetOrCreatePersistentKey()
    
    ; Obfuscate directory names using hash
    dirHash := HashString(MACHINE_KEY . A_ComputerName)
    APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content\{" SubStr(dirHash, 1, 8) "}"
    SECURE_VAULT := APP_DIR "\{" SubStr(dirHash, 9, 8) "}"
    BASE_DIR := SECURE_VAULT "\dat"
    ICON_DIR := SECURE_VAULT "\res"
    VERSION_FILE := SECURE_VAULT "\~ver.tmp"
    
    ; Initialize auth file paths
    CRED_FILE := SECURE_VAULT "\.sysauth"
    SESSION_FILE := SECURE_VAULT "\.session"
    DISCORD_ID_FILE := SECURE_VAULT "\discord_id.txt"
    DISCORD_BAN_FILE := SECURE_VAULT "\banned_discord_ids.txt"
    ADMIN_DISCORD_FILE := SECURE_VAULT "\admin_discord_ids.txt"
    SESSION_LOG_FILE := SECURE_VAULT "\sessions.log"
    MACHINE_BAN_FILE := SECURE_VAULT "\.machine_banned"
    HWID_BINDING_FILE := SECURE_VAULT "\.hwid_bind"
    LAST_CRED_HASH_FILE := SECURE_VAULT "\.last_cred_hash"
    SECURE_CONFIG_FILE := SECURE_VAULT "\.secure_config"
    ENCRYPTED_KEY_FILE := SECURE_VAULT "\.enckey"
    MASTER_KEY_ROTATION_FILE := SECURE_VAULT "\.key_rotation"
    
    try {
        DirCreate APP_DIR
        DirCreate SECURE_VAULT
        DirCreate BASE_DIR
        DirCreate ICON_DIR
        
        ; Hide AND mark as system files
        RunWait 'attrib +h +s +r "' APP_DIR '"', , "Hide"
        RunWait 'attrib +h +s +r "' SECURE_VAULT '"', , "Hide"
        RunWait 'attrib +h +s +r "' BASE_DIR '"', , "Hide"
        RunWait 'attrib +h +s +r "' ICON_DIR '"', , "Hide"
        
        ; Set restrictive permissions
        RunWait 'icacls "' SECURE_VAULT '" /inheritance:r /grant:r "' A_UserName '":F', , "Hide"
    } catch as err {
        MsgBox "Failed to initialize secure vault: " err.Message, "Security Error", "Icon!"
        ExitApp
    }
    
    EnsureVersionFile()
    
    ; Initialize secure config
    LoadSecureConfig()
}

GenerateMachineKey() {
    ; Multi-layer hardware fingerprint
    hwid := A_ComputerName . A_UserName . A_OSVersion
    
    ; Add CPU info if available
    try {
        cpu := ComObjGet("winmgmts:").ExecQuery("SELECT * FROM Win32_Processor")
        for proc in cpu
            hwid .= proc.ProcessorId
    }
    
    ; Add disk serial
    try {
        disk := ComObjGet("winmgmts:").ExecQuery("SELECT * FROM Win32_DiskDrive")
        for d in disk {
            hwid .= d.SerialNumber
            break
        }
    }
    
    ; Hash multiple times for obfuscation
    key := HashString(hwid)
    loop 100
        key := HashString(key . hwid . A_Index)
    
    return key
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
        
        ; Load key history
        try {
            historyStr := RegRead(regPath, regKeyHistory)
            if (historyStr) {
                for key in StrSplit(historyStr, "|") {
                    if (key && StrLen(key) >= 32) {
                        KEY_HISTORY.Push(key)
                    }
                }
            }
        }
        
        ; Check if 3 days have passed
        daysDiff := DateDiff(currentDate, lastRotation, "Days")
        
        if (daysDiff >= 3) {
            shouldRotate := true
        }
    } catch {
        shouldRotate := true
    }
    
    if (shouldRotate || !currentKey || StrLen(currentKey) < 32) {
        ; Save old key to history before rotating
        if (currentKey && StrLen(currentKey) >= 32) {
            KEY_HISTORY.Push(currentKey)
            
            ; Keep only last 10 keys (30 days of history)
            if (KEY_HISTORY.Length > 10) {
                KEY_HISTORY.RemoveAt(1)
            }
        }
        
        ; Generate new key
        newKey := GenerateMachineKey()
        
        try {
            RegWrite newKey, "REG_SZ", regPath, regCurrentKey
            RegWrite currentDate, "REG_SZ", regPath, regDateValue
            
            ; Save key history
            historyStr := ""
            for key in KEY_HISTORY {
                historyStr .= key "|"
            }
            RegWrite historyStr, "REG_SZ", regPath, regKeyHistory
            
            return newKey
        } catch {
            return newKey
        }
    }
    
    return currentKey
}

DateDiff(date1, date2, unit := "Days") {
    ; Convert dates to comparable format
    d1 := SubStr(date1, 1, 8)
    d2 := SubStr(date2, 1, 8)
    
    ; Parse dates
    y1 := SubStr(d1, 1, 4)
    m1 := SubStr(d1, 5, 2)
    day1 := SubStr(d1, 7, 2)
    
    y2 := SubStr(d2, 1, 4)
    m2 := SubStr(d2, 5, 2)
    day2 := SubStr(d2, 7, 2)
    
    ; Calculate difference in days (approximate)
    diff := (y1 - y2) * 365 + (m1 - m2) * 30 + (day1 - day2)
    
    return Abs(diff)
}

DPAPIEncrypt(plaintext) {
    if !plaintext
        return ""
    
    try {
        dataSize := StrPut(plaintext, "UTF-16") * 2
        pData := Buffer(dataSize)
        StrPut(plaintext, pData, "UTF-16")
        
        dataIn := Buffer(16)
        NumPut("UInt", dataSize, dataIn, 0)
        NumPut("Ptr", pData.Ptr, dataIn, 8)
        
        dataOut := Buffer(16)
        
        result := DllCall("Crypt32\CryptProtectData",
            "Ptr", dataIn,
            "Ptr", 0,
            "Ptr", 0,
            "Ptr", 0,
            "Ptr", 0,
            "UInt", 1,
            "Ptr", dataOut,
            "Int")
        
        if !result
            throw Error("CryptProtectData failed")
        
        encSize := NumGet(dataOut, 0, "UInt")
        encPtr := NumGet(dataOut, 8, "Ptr")
        
        encData := ""
        loop encSize {
            byte := NumGet(encPtr + A_Index - 1, "UChar")
            encData .= Format("{:02X}", byte)
        }
        
        DllCall("LocalFree", "Ptr", encPtr)
        
        return encData
    } catch as err {
        return ""
    }
}

DPAPIDecrypt(hexData) {
    if !hexData
        return ""
    
    try {
        dataSize := StrLen(hexData) // 2
        pData := Buffer(dataSize)
        
        loop dataSize {
            hexByte := SubStr(hexData, (A_Index - 1) * 2 + 1, 2)
            NumPut("UChar", Integer("0x" hexByte), pData, A_Index - 1)
        }
        
        dataIn := Buffer(16)
        NumPut("UInt", dataSize, dataIn, 0)
        NumPut("Ptr", pData.Ptr, dataIn, 8)
        
        dataOut := Buffer(16)
        
        result := DllCall("Crypt32\CryptUnprotectData",
            "Ptr", dataIn,
            "Ptr", 0,
            "Ptr", 0,
            "Ptr", 0,
            "Ptr", 0,
            "UInt", 1,
            "Ptr", dataOut,
            "Int")
        
        if !result
            throw Error("CryptUnprotectData failed")
        
        decSize := NumGet(dataOut, 0, "UInt")
        decPtr := NumGet(dataOut, 8, "Ptr")
        
        plaintext := StrGet(decPtr, decSize // 2, "UTF-16")
        
        DllCall("LocalFree", "Ptr", decPtr)
        
        return plaintext
    } catch as err {
        return ""
    }
}

HashString(str) {
    hash := 0
    for char in StrSplit(str) {
        hash := Mod(hash * 31 + Ord(char), 0xFFFFFFFF)
    }
    return Format("{:08X}", hash)
}

XOREncrypt(data, key) {
    if (!data || !key)
        return ""
    
    result := ""
    keyLen := StrLen(key)
    dataLen := StrLen(data)
    
    loop dataLen {
        dataChar := Ord(SubStr(data, A_Index, 1))
        keyChar := Ord(SubStr(key, Mod(A_Index - 1, keyLen) + 1, 1))
        result .= Chr(dataChar ^ keyChar)
    }
    
    return result
}

CreateGUID() {
    guid := ""
    loop 32 {
        guid .= Format("{:X}", Random(0, 15))
        if (A_Index = 8 || A_Index = 12 || A_Index = 16 || A_Index = 20)
            guid .= "-"
    }
    return guid
}

SecureFileWrite(path, content) {
    global MACHINE_KEY
    
    try {
        ; Remove attributes before writing if file exists
        if FileExist(path) {
            RunWait 'attrib -h -s -r "' path '"', , "Hide"
            FileDelete path
        }
        
        ; First layer: XOR with machine key
        obfuscated := XOREncrypt(content, MACHINE_KEY)
        
        ; Second layer: Windows DPAPI
        encrypted := DPAPIEncrypt(obfuscated)
        
        if !encrypted
            throw Error("Encryption failed")
        
        ; Write with random padding
        padding := ""
        loop Random(50, 200)
            padding .= Chr(Random(0, 255))
        
        finalData := padding . "|SECURE|" . encrypted . "|END|" . padding
        
        FileAppend finalData, path
        RunWait 'attrib +h +s +r "' path '"', , "Hide"
    } catch as err {
        throw Error("Secure write failed: " err.Message)
    }
}

TryDecryptWithKey(encrypted, key) {
    try {
        obfuscated := DPAPIDecrypt(encrypted)
        if !obfuscated
            return ""
        
        decrypted := XOREncrypt(obfuscated, key)
        
        ; Basic validation - check if result looks like text
        if (decrypted && StrLen(decrypted) > 0)
            return decrypted
        
        return ""
    } catch {
        return ""
    }
}

SecureFileRead(path) {
    global MACHINE_KEY, KEY_HISTORY
    
    if !FileExist(path)
        return ""
    
    try {
        rawData := FileRead(path)
        
        if !InStr(rawData, "|SECURE|") || !InStr(rawData, "|END|")
            return ""
        
        RegExMatch(rawData, "\|SECURE\|(.*?)\|END\|", &match)
        if !match
            return ""
        
        encrypted := match[1]
        
        ; Try current key first
        decrypted := TryDecryptWithKey(encrypted, MACHINE_KEY)
        if (decrypted)
            return decrypted
        
        ; Try historical keys
        if (KEY_HISTORY.Length > 0) {
            for oldKey in KEY_HISTORY {
                decrypted := TryDecryptWithKey(encrypted, oldKey)
                if (decrypted)
                    return decrypted
            }
        }
        
        return ""
    } catch {
        return ""
    }
}
; ================= BAN MANAGEMENT =================

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
RefreshBannedHwidLabel(lblCtrl) {
    global HWID_BAN_FILE

    if !FileExist(HWID_BAN_FILE) {
        lblCtrl.Value := "Banned HWIDs: (none)"
        return
    }

    ids := GetLinesFromFile(HWID_BAN_FILE)
    if (ids.Length = 0) {
        lblCtrl.Value := "Banned HWIDs: (none)"
        return
    }

    s := "Banned HWIDs: "
    for id in ids
        s .= id ", "
    lblCtrl.Value := RTrim(s, ", ")
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
    OverwriteListFile(HWID_BAN_FILE, lists.banned_hwids)

    return lists
}
EncryptMacroFile(path) {
    if !FileExist(path)
        return false
    
    try {
        content := FileRead(path)
        
        ; Remove read-only attribute before deleting
        try RunWait 'attrib -r "' path '"', , "Hide"
        FileDelete path
        SecureFileWrite(path, content)
        return true
    } catch {
        return false
    }
    
    return false
}

DecryptMacroForExecution(path) {
    if !FileExist(path)
        return ""
    
    try {
        content := SecureFileRead(path)
        if !content
            return path  ; Return original if decryption fails
        
        ; Use less predictable temp name with immediate deletion timer
        tempPath := A_Temp "\~" . Format("{:08X}", Random(0, 0xFFFFFFFF)) . ".ahk"
        
        ; Set aggressive cleanup
        SetTimer () => DeleteSecurely(tempPath), -5000  ; Delete after 5 seconds instead of 30
        
        FileAppend content, tempPath
        
        ; Try to set delete-on-close attribute (Windows only, may fail)
        try {
            RunWait 'attrib +s +h "' tempPath '"', , "Hide"
        }
        
        return tempPath
    } catch {
        return path
    }
}

DeleteSecurely(path) {
    if !FileExist(path)
        return
    
    try {
        size := FileGetSize(path)
        randomData := ""
        loop Min(size, 1000) {
            randomData .= Chr(Random(0, 255))
        }
        
        FileDelete path
        FileAppend randomData, path
        FileDelete path
    } catch {
    }
}

EncryptAllMacros() {
    global BASE_DIR
    
    try {
        Loop Files, BASE_DIR "\*\*.ahk", "R" {
            EncryptMacroFile(A_LoopFilePath)
        }
    } catch {
    }
}

; ============= CORE FUNCTIONS =============
EnsureVersionFile() {
    global VERSION_FILE
    
    if !FileExist(VERSION_FILE) {
        try {
            versionData := "0|" . A_Now
            SecureFileWrite(VERSION_FILE, versionData)
        } catch {
        }
    }
}

GetSecureVersion() {
    global VERSION_FILE
    
    try {
        versionData := SecureFileRead(VERSION_FILE)
        if !versionData
            return "0"
        
        parts := StrSplit(versionData, "|")
        return parts.Has(1) ? parts[1] : "0"
    } catch {
        return "0"
    }
}

SetTaskbarIcon() {
    global ICON_DIR
    iconPath := ICON_DIR "\Launcher.png"
    
    try {
        if FileExist(iconPath) {
            TraySetIcon(iconPath)
        } else {
            TraySetIcon("shell32.dll", 3)
        }
    } catch {
    }
}

SetupTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open Admin Panel (Ctrl+Alt+P)", (*) => AdminPanel())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
}

CheckForUpdatesPrompt() {
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, APP_DIR, ICON_DIR

    tmpManifest := A_Temp "\manifest.json"
    tmpZip := A_Temp "\Macros.zip"
    extractDir := A_Temp "\macro_extract"
    backupDir := A_Temp "\macro_backup_" A_Now

    if !SafeDownload(MANIFEST_URL, tmpManifest) {
        return
    }

    try json := FileRead(tmpManifest, "UTF-8")
    catch {
        return
    }

    manifest := ParseManifest(json)
    if !manifest
        return

    current := GetSecureVersion()

    if VersionCompare(manifest.version, current) <= 0
        return

    changelogText := ""
    for line in manifest.changelog
        changelogText .= "• " line "`n"

    choice := MsgBox(
        "Update available!`n`n"
        . "Current: " current "`n"
        . "Latest: " manifest.version "`n`n"
        . "What's new:`n" changelogText "`n"
        . "Do you want to update now?",
        "AHK vault Update",
        "YesNo Iconi"
    )
    if (choice = "No")
        return

    downloadSuccess := false
    attempts := 0
    maxAttempts := 3

    while (!downloadSuccess && attempts < maxAttempts) {
        attempts++
        if SafeDownload(manifest.zip_url, tmpZip, 30000) && IsValidZip(tmpZip) {
            downloadSuccess := true
        } else {
            try if FileExist(tmpZip) FileDelete(tmpZip)
            if (attempts < maxAttempts)
                Sleep 1000
        }
    }

    if !downloadSuccess {
        MsgBox(
            "Failed to download a valid ZIP after " maxAttempts " attempts.`n`n"
            . "Zip URL:`n" manifest.zip_url,
            "Download Failed",
            "Icon!"
        )
        return
    }

    try {
        if DirExist(extractDir)
            DirDelete extractDir, true
        DirCreate extractDir
    } catch as err {
        ShowUpdateFail("Create extraction directory", err, "extractDir=`n" extractDir)
        return
    }

    extractSuccess := false
    try {
        RunWait 'tar -xf "' tmpZip '" -C "' extractDir '"', , "Hide"
        extractSuccess := DirExist(extractDir) && HasAnyFolders(extractDir)
    } catch {
        extractSuccess := false
    }

    if !extractSuccess {
        try {
            psCmd := 'powershell -Command "Expand-Archive -Path `"' tmpZip '`" -DestinationPath `"' extractDir '`" -Force"'
            RunWait psCmd, , "Hide"
            extractSuccess := DirExist(extractDir) && HasAnyFolders(extractDir)
        } catch as err {
            ShowUpdateFail("Extraction (tar + PowerShell)", err, "zip=`n" tmpZip "`nextractDir=`n" extractDir)
            return
        }
    }

    if !extractSuccess {
        MsgBox "Update failed: extraction produced no folders.", "Error", "Icon!"
        return
    }

    hasMacrosFolder := DirExist(extractDir "\Macros")
    hasIconsFolder := DirExist(extractDir "\icons")
    hasLooseFolders := HasAnyFolders(extractDir)

    useNestedStructure := hasMacrosFolder
    if (!hasMacrosFolder && !hasLooseFolders) {
        MsgBox "Update failed: No valid content found in zip file.", "Error", "Icon!"
        return
    }

    backupSuccess := false
    if DirExist(BASE_DIR) {
        try {
            DirCreate backupDir
            Loop Files, BASE_DIR "\*", "D"
                TryDirMove(A_LoopFilePath, backupDir "\" A_LoopFileName, true)
            backupSuccess := true
        } catch as err {
            backupSuccess := false
        }
    }

    try {
        if DirExist(BASE_DIR)
            DirDelete BASE_DIR, true
        DirCreate BASE_DIR

        if useNestedStructure {
            Loop Files, extractDir "\Macros\*", "D"
                TryDirMove(A_LoopFilePath, BASE_DIR "\" A_LoopFileName, true)
        } else {
            Loop Files, extractDir "\*", "D" {
                if (A_LoopFileName != "icons")
                    TryDirMove(A_LoopFilePath, BASE_DIR "\" A_LoopFileName, true)
            }
        }
        
        EncryptAllMacros()
        
    } catch as err {
        try {
            if backupSuccess {
                if DirExist(BASE_DIR)
                    DirDelete BASE_DIR, true
                DirCreate BASE_DIR
                Loop Files, backupDir "\*", "D"
                    TryDirMove(A_LoopFilePath, BASE_DIR "\" A_LoopFileName, true)
            }
        } catch {
        }

        ShowUpdateFail("Install / move folders", err, "BASE_DIR=`n" BASE_DIR "`n`nextractDir=`n" extractDir)
        return
    }

    iconsUpdated := false
    if hasIconsFolder {
        try {
            if !DirExist(ICON_DIR)
                DirCreate ICON_DIR
            Loop Files, extractDir "\icons\*.*", "F" {
                TryFileCopy(A_LoopFilePath, ICON_DIR "\" A_LoopFileName, true)
                iconsUpdated := true
            }
        } catch as err {
            ShowUpdateFail("Copy icons", err, "ICON_DIR=`n" ICON_DIR)
        }
    }

    try {
        ; Remove attributes before writing
        if FileExist(VERSION_FILE) {
            RunWait 'attrib -h -s -r "' VERSION_FILE '"', , "Hide"
        }
        
        versionData := manifest.version . "|" . A_Now
        SecureFileWrite(VERSION_FILE, versionData)
        RunWait 'attrib +h +s +r "' VERSION_FILE '"', , "Hide"
        RunWait 'attrib +h +s +r "' APP_DIR '"', , "Hide"
    } catch as err {
        ShowUpdateFail("Write version file", err, "VERSION_FILE=`n" VERSION_FILE)
    }

    try {
        if FileExist(tmpZip)
            FileDelete tmpZip
        if DirExist(extractDir)
            DirDelete extractDir, true
    } catch {
    }

    updateMsg := "Update complete!`n`nVersion " manifest.version " installed.`n`n"
    if iconsUpdated
        updateMsg .= "✓ Icons updated`n"
    updateMsg .= "✓ Files encrypted`n`n"
    updateMsg .= "Changes:`n" changelogText

    MsgBox updateMsg, "Update Finished", "Iconi"
}

HasAnyFolders(dir) {
    try {
        Loop Files, dir "\*", "D"
            return true
    }
    return false
}

; ================= ADMIN MANAGEMENT =================

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

; ================= SESSION LOG =================

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

; ================= ADMIN PANEL EVENT HANDLERS =================
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

ManualUpdate(*) {
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, APP_DIR, ICON_DIR
    
    choice := MsgBox(
        "Check for macro updates?`n`n"
        "This will download the latest macros from the repository.",
        "Check for Updates",
        "YesNo Iconi"
    )
    
    if (choice = "No") {
        return
    }
    
    tmpManifest := A_Temp "\manifest.json"
    tmpZip := A_Temp "\Macros.zip"
    extractDir := A_Temp "\macro_extract"
    backupDir := A_Temp "\macro_backup_" A_Now
    
    if !SafeDownload(MANIFEST_URL, tmpManifest) {
        MsgBox(
            "Failed to download update information.`n`n"
            "Please check your internet connection.`n`n"
            "Manifest URL: " MANIFEST_URL,
            "Download Failed",
            "Icon!"
        )
        return
    }
    
    json := ""
    try {
        json := FileRead(tmpManifest, "UTF-8")
    } catch {
        MsgBox "Failed to read update information.", "Error", "Icon!"
        return
    }
    
    manifest := ParseManifest(json)
    if !manifest {
        MsgBox "Failed to parse update information.", "Error", "Icon!"
        return
    }
    
    changelogText := ""
    for line in manifest.changelog {
        changelogText .= "• " line "`n"
    }
    
    choice := MsgBox(
        "Update available!`n`n"
        "Latest: " manifest.version "`n`n"
        "What's new:`n" changelogText "`n"
        "Download and install now?",
        "Update Available",
        "YesNo Iconi"
    )
    
    if (choice = "No") {
        return
    }
    
    downloadSuccess := false
    attempts := 0
    maxAttempts := 3
    
    while (!downloadSuccess && attempts < maxAttempts) {
        attempts++
        
        if SafeDownload(manifest.zip_url, tmpZip, 30000) {
            try {
                fileSize := 0
                Loop Files, tmpZip
                    fileSize := A_LoopFileSize
                
                if (fileSize >= 100) {
                    downloadSuccess := true
                } else {
                    try FileDelete tmpZip
                    if (attempts < maxAttempts) {
                        Sleep 1000
                    }
                }
            } catch {
                if (attempts < maxAttempts) {
                    Sleep 1000
                }
            }
        }
    }
    
    if !downloadSuccess {
        MsgBox(
            "Failed to download update after " maxAttempts " attempts.`n`n"
            "Please check your internet connection and try again later.`n`n"
            "Zip URL: " manifest.zip_url,
            "Download Failed",
            "Icon!"
        )
        return
    }
    
    try {
        if DirExist(extractDir) {
            DirDelete extractDir, true
        }
        DirCreate extractDir
    } catch as err {
        MsgBox "Failed to create extraction directory: " err.Message, "Error", "Icon!"
        return
    }
    
    extractSuccess := false
    try {
        RunWait 'tar -xf "' tmpZip '" -C "' extractDir '"', , "Hide"
        
        hasContent := false
        try {
            Loop Files, extractDir "\*", "D" {
                hasContent := true
                break
            }
        }
        extractSuccess := hasContent
    } catch {
    }
    
    if !extractSuccess {
        try {
            psCmd := 'powershell -Command "Expand-Archive -Path `"' tmpZip '`" -DestinationPath `"' extractDir '`" -Force"'
            RunWait psCmd, , "Hide"
            
            hasContent := false
            try {
                Loop Files, extractDir "\*", "D" {
                    hasContent := true
                    break
                }
            }
            extractSuccess := hasContent
        } catch {
            MsgBox(
                "Failed to extract update archive.`n`n"
                "Both tar and PowerShell extraction methods failed.",
                "Extraction Failed",
                "Icon!"
            )
            return
        }
    }
    
    if !extractSuccess {
        MsgBox "Update failed: extraction produced no folders.", "Error", "Icon!"
        return
    }
    
    hasMacrosFolder := false
    hasIconsFolder := false
    hasLooseFolders := false
    
    try {
        if DirExist(extractDir "\Macros") {
            hasMacrosFolder := true
        }
        if DirExist(extractDir "\icons") {
            hasIconsFolder := true
        }
        
        Loop Files, extractDir "\*", "D" {
            if (A_LoopFileName != "Macros" && A_LoopFileName != "icons") {
                hasLooseFolders := true
                break
            }
        }
    }
    
    useNestedStructure := hasMacrosFolder
    
    if (!hasMacrosFolder && !hasLooseFolders) {
        MsgBox "Update failed: No valid content found in zip file.", "Error", "Icon!"
        return
    }
    
    backupSuccess := false
    if DirExist(BASE_DIR) {
        try {
            DirCreate backupDir
            Loop Files, BASE_DIR "\*", "D" {
                DirMove A_LoopFilePath, backupDir "\" A_LoopFileName, 1
            }
            backupSuccess := true
        } catch {
        }
    }
    
    installSuccess := false
    try {
        if DirExist(BASE_DIR) {
            DirDelete BASE_DIR, true
        }
        DirCreate BASE_DIR
        
        if useNestedStructure {
            Loop Files, extractDir "\Macros\*", "D" {
                DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName, 1
            }
        } else {
            Loop Files, extractDir "\*", "D" {
                if (A_LoopFileName != "icons") {
                    DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName, 1
                }
            }
        }
        
        EncryptAllMacros()
        installSuccess := true
    } catch as err {
        MsgBox "Failed to install macro update: " err.Message, "Error", "Icon!"
        
        if backupSuccess {
            try {
                if DirExist(BASE_DIR) {
                    DirDelete BASE_DIR, true
                }
                DirCreate BASE_DIR
                
                Loop Files, backupDir "\*", "D" {
                    DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName, 1
                }
                MsgBox "Update failed but your macros were restored from backup.", "Restored", "Iconi"
            } catch {
                MsgBox(
                    "Critical error: Update failed and rollback failed.`n`n"
                    "Backup location:`n" backupDir,
                    "Critical Error",
                    "Icon!"
                )
            }
        }
        return
    }
    
    iconsUpdated := false
    iconBackupDir := A_Temp "\icon_backup_" A_Now
    iconBackupSuccess := false
    
    if DirExist(extractDir "\icons") {
        try {
            if DirExist(ICON_DIR) {
                DirCreate iconBackupDir
                Loop Files, ICON_DIR "\*.*" {
                    FileCopy A_LoopFilePath, iconBackupDir "\" A_LoopFileName, 1
                }
                iconBackupSuccess := true
            }
        }
        
        try {
            if !DirExist(ICON_DIR) {
                DirCreate ICON_DIR
            }
        }
        
        try {
            iconCount := 0
            Loop Files, extractDir "\icons\*.*" {
                FileCopy A_LoopFilePath, ICON_DIR "\" A_LoopFileName, 1
                iconCount++
            }
            
            if (iconCount > 0) {
                iconsUpdated := true
            }
            
            if iconBackupSuccess && DirExist(iconBackupDir) {
                try {
                    DirDelete iconBackupDir, true
                }
            }
        } catch as err {
            if iconBackupSuccess {
                try {
                    Loop Files, iconBackupDir "\*.*" {
                        FileCopy A_LoopFilePath, ICON_DIR "\" A_LoopFileName, 1
                    }
                }
            }
        }
    }
    
    if installSuccess && backupSuccess {
        try {
            if DirExist(backupDir) {
                DirDelete backupDir, true
            }
        }
    }
    
    try {
        ; Remove attributes before writing
        if FileExist(VERSION_FILE) {
            RunWait 'attrib -h -s -r "' VERSION_FILE '"', , "Hide"
        }
        
        versionData := manifest.version . "|" . A_Now
        SecureFileWrite(VERSION_FILE, versionData)
        RunWait 'attrib +h +s +r "' VERSION_FILE '"', , "Hide"
        RunWait 'attrib +h +s +r "' APP_DIR '"', , "Hide"
    } catch as err {
        ShowUpdateFail("Write version file", err, "VERSION_FILE=`n" VERSION_FILE)
    }
    
    try {
        if FileExist(tmpZip) {
            FileDelete tmpZip
        }
        if DirExist(extractDir) {
            DirDelete extractDir, true
        }
    }
    
    updateMsg := "Update complete!`n`nVersion " manifest.version " installed.`n`n"
    if iconsUpdated {
        updateMsg .= "✓ Icons updated`n"
    }
    updateMsg .= "✓ Files encrypted`n`n"
    updateMsg .= "Changes:`n" changelogText "`n`nRestart the launcher to see changes."
    
    MsgBox(updateMsg, "Update Finished", "Iconi")
    
    try {
        mainGui.Destroy()
        CreateMainGui()
    }
}

DecryptManifestUrl() {
    ; Encrypted manifest URL (obfuscated)
    encrypted := "68747470733A2F2F7261772E67697468756275736572636F6E74656E742E636F6D2F6C6577697377723"
               . "22F6175746F686F746B65792D73747566662D636861742F6D61696E2F6D616E69666573742E6A736F6E"
    
    ; Decrypt hex to URL
    url := ""
    pos := 1
    while (pos <= StrLen(encrypted)) {
        hex := SubStr(encrypted, pos, 2)
        url .= Chr("0x" hex)
        pos += 2
    }
    
    return url
}

SafeDownload(url, out, timeoutMs := 10000) {
    if !url || !out {
        return false
    }
    
    try {
        if FileExist(out) {
            FileDelete out
        }
        
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

ParseManifest(json) {
    if !json {
        return false
    }
    
    manifest := {
        version: "",
        zip_url: "",
        changelog: []
    }
    
    try {
        if RegExMatch(json, '"version"\s*:\s*"([^"]+)"', &m) {
            manifest.version := m[1]
        }
        
        if RegExMatch(json, '"zip_url"\s*:\s*"([^"]+)"', &m) {
            manifest.zip_url := m[1]
        }
        
        pat := 's)"changelog"\s*:\s*\[(.*?)\]'
        if RegExMatch(json, pat, &m) {
            block := m[1]
            pos := 1
            while RegExMatch(block, 's)"((?:\\.|[^"\\])*)"', &mm, pos) {
                item := mm[1]
                item := StrReplace(item, '\"', '"')
                item := StrReplace(item, "\\", "\")
                item := StrReplace(item, "\n", "`n")
                item := StrReplace(item, "\r", "`r")
                manifest.changelog.Push(item)
                pos := mm.Pos + mm.Len
            }
        }
    } catch {
        return false
    }
    
    if (!manifest.version || !manifest.zip_url) {
        return false
    }
    
    return manifest
}

CreateMainGui() {
    global mainGui, COLORS, BASE_DIR, ICON_DIR
    
    mainGui := Gui("-Resize +Border", " AHK VAULT")
    mainGui.BackColor := COLORS.bg
    mainGui.SetFont("s10", "Segoe UI")
    
    iconPath := ICON_DIR "\1.png"
    if FileExist(iconPath) {
        try {
            mainGui.Show("Hide")
            mainGui.Opt("+Icon" iconPath)
        }
    }
    
    mainGui.Add("Text", "x0 y0 w550 h80 Background" COLORS.accent)
    
    ahkImage := ICON_DIR "\AHK.png"
    if FileExist(ahkImage) {
        try {
            mainGui.Add("Picture", "x20 y15 w50 h50 BackgroundTrans", ahkImage)
        }
    }
    
    titleText := mainGui.Add("Text", "x80 y20 w280 h100 c" COLORS.text " BackgroundTrans", " AHK VAULT")
    titleText.SetFont("s24 bold")

    btnNuke := mainGui.Add("Button", "x290 y25 w75 h35 Background" COLORS.danger, "Uninstall")
    btnNuke.SetFont("s9")
    btnNuke.OnEvent("Click", CompleteUninstall)

    btnUpdate := mainGui.Add("Button", "x370 y25 w75 h35 Background" COLORS.success, "Update")
    btnUpdate.SetFont("s10")
    btnUpdate.OnEvent("Click", ManualUpdate)
    
    btnLog := mainGui.Add("Button", "x450 y25 w75 h35 Background" COLORS.accentHover, "Changelog")
    btnLog.SetFont("s10")
    btnLog.OnEvent("Click", ShowChangelog)

    mainGui.Add("Text", "x25 y100 w500 c" COLORS.text, "Games").SetFont("s12 bold")
    mainGui.Add("Text", "x25 y125 w500 h1 Background" COLORS.border)
    
    categories := GetCategories()
    yPos := 145
    xPos := 25
    cardWidth := 500
    cardHeight := 70
    
    if (categories.Length = 0) {
        noGameText := mainGui.Add("Text", "x25 y145 w500 h120 c" COLORS.textDim " Center", 
            "No game categories found`n`nPlace game folders in the secure vault")
        noGameText.SetFont("s10")
        yPos := 275
    } else {
        for category in categories {
            CreateCategoryCard(mainGui, category, xPos, yPos, cardWidth, cardHeight)
            yPos += cardHeight + 12
        }
    }
    
    bottomY := yPos + 15
    mainGui.Add("Text", "x0 y" bottomY " w550 h1 Background" COLORS.border)
    
    linkY := bottomY + 15
    CreateLink(mainGui, "Discord", "https://discord.gg/PQ85S32Ht8", 25, linkY)
    
    mainGui.Show("w550 h" (bottomY + 60) " Center")
}

GetCategories() {
    global BASE_DIR
    arr := []
    
    if !DirExist(BASE_DIR) {
        return arr
    }
    
    try {
        Loop Files, BASE_DIR "\*", "D" {
            if (StrLower(A_LoopFileName) = "icons") {
                continue
            }
            arr.Push(A_LoopFileName)
        }
    }
    
    return arr
}

CreateCategoryCard(gui, category, x, y, w, h) {
    global COLORS
    
    card := gui.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    
    iconPath := GetGameIcon(category)
    iconX := x + 15
    iconY := y + 15
    iconSize := 40
    
    if (iconPath && FileExist(iconPath)) {
        try {
            gui.Add("Picture", "x" iconX " y" iconY " w" iconSize " h" iconSize " BackgroundTrans", iconPath)
        } catch {
            CreateCategoryBadge(gui, category, iconX, iconY, iconSize)
        }
    } else {
        CreateCategoryBadge(gui, category, iconX, iconY, iconSize)
    }
    
    titleText := gui.Add("Text", "x" (x + 70) " y" (y + 22) " w" (w - 150) " c" COLORS.text " BackgroundTrans", category)
    titleText.SetFont("s11 bold")
    
    openBtn := gui.Add("Button", "x" (x + w - 95) " y" (y + 18) " w80 h34 Background" COLORS.accent, "Open →")
    openBtn.SetFont("s9 bold")
    openBtn.OnEvent("Click", (*) => OpenCategory(category))
}

CreateCategoryBadge(gui, category, x, y, size := 40) {
    global COLORS
    
    initial := SubStr(category, 1, 1)
    iconColor := GetCategoryColor(category)
    
    badge := gui.Add("Text", "x" x " y" y " w" size " h" size " Background" iconColor " Center", initial)
    badge.SetFont("s18 bold c" COLORS.text)
    
    return badge
}

GetGameIcon(category) {
    global ICON_DIR, BASE_DIR
    
    extensions := ["png", "ico", "jpg", "jpeg"]
    
    for ext in extensions {
        iconPath := ICON_DIR "\" category "." ext
        if FileExist(iconPath) {
            return iconPath
        }
    }
    
    for ext in extensions {
        iconPath := BASE_DIR "\" category "." ext
        if FileExist(iconPath) {
            return iconPath
        }
    }
    
    for ext in extensions {
        iconPath := BASE_DIR "\" category "\icon." ext
        if FileExist(iconPath) {
            return iconPath
        }
    }
    
    return ""
}

GetCategoryColor(category) {
    colors := ["0x238636", "0x1f6feb", "0x8957e5", "0xda3633", "0xbc4c00", "0x1a7f37", "0xd29922"]
    
    hash := 0
    for char in StrSplit(category) {
        hash += Ord(char)
    }
    
    return colors[Mod(hash, colors.Length) + 1]
}

CreateLink(gui, label, url, x, y) {
    global COLORS
    
    link := gui.Add("Text", "x" x " y" y " c" COLORS.accent " BackgroundTrans", label)
    link.SetFont("s9 underline")
    link.OnEvent("Click", (*) => SafeOpenURL(url))
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

OpenCategory(category) {
    global COLORS, BASE_DIR
    
    macros := GetMacrosWithInfo(category)
    
    if (macros.Length = 0) {
        MsgBox(
            "No macros found in '" category "'`n`n"
            "To add macros:`n"
            "1. Create a 'Main.ahk' file in each subfolder`n"
            "2. Or run the update to download macros",
            "No Macros",
            "Iconi"
        )
        return
    }
    
    win := Gui("-Resize +Border", category " - Macros [SECURE]")
    win.BackColor := COLORS.bg
    win.SetFont("s10", "Segoe UI")
    
    win.__data := macros
    win.__cards := []
    win.__currentPage := 1
    win.__itemsPerPage := 8
    
    gameIcon := GetGameIcon(category)
    if (gameIcon && FileExist(gameIcon)) {
        try {
            win.Show("Hide")
            win.Opt("+Icon" gameIcon)
        }
    }
    
    win.Add("Text", "x0 y0 w750 h90 Background" COLORS.accent)
    
    backBtn := win.Add("Button", "x20 y25 w70 h35 Background" COLORS.accentHover, "← Back")
    backBtn.SetFont("s10")
    backBtn.OnEvent("Click", (*) => win.Destroy())
    
    title := win.Add("Text", "x105 y20 w500 h100 c" COLORS.text " BackgroundTrans", category)
    title.SetFont("s22 bold")
    
    win.__scrollY := 110
    
    win.OnEvent("Close", (*) => win.Destroy())
    
    RenderCards(win)
    
    win.Show("w750 h640 Center")
}

RenderCards(win) {
    global COLORS
    
    if !win.HasProp("__data") {
        return
    }
    
    if win.HasProp("__cards") && win.__cards.Length > 0 {
        for ctrl in win.__cards {
            try {
                ctrl.Destroy()
            } catch {
            }
        }
    }
    win.__cards := []
    
    macros := win.__data
    scrollY := win.__scrollY
    
    if (macros.Length = 0) {
        noResult := win.Add("Text", "x25 y" scrollY " w700 h100 c" COLORS.textDim " Center", 
            "No macros found")
        noResult.SetFont("s10")
        win.__cards.Push(noResult)
        return
    }
    
    itemsPerPage := win.__itemsPerPage
    currentPage := win.__currentPage
    totalPages := Ceil(macros.Length / itemsPerPage)
    
    if (currentPage > totalPages) {
        currentPage := totalPages
        win.__currentPage := currentPage
    }
    
    startIdx := ((currentPage - 1) * itemsPerPage) + 1
    endIdx := Min(currentPage * itemsPerPage, macros.Length)
    
    itemsToShow := endIdx - startIdx + 1
    
    if (itemsToShow = 1) {
        item := macros[startIdx]
        CreateFullWidthCard(win, item, 25, scrollY, 700, 110)
    } else {
        cardWidth := 340
        cardHeight := 110
        spacing := 10
        yPos := scrollY
        
        Loop itemsToShow {
            idx := startIdx + A_Index - 1
            item := macros[idx]
            
            col := Mod(A_Index - 1, 2)
            row := Floor((A_Index - 1) / 2)
            
            xPos := 25 + (col * (cardWidth + spacing))
            yPos := scrollY + (row * (cardHeight + spacing))
            
            CreateGridCard(win, item, xPos, yPos, cardWidth, cardHeight)
        }
    }
    
    if (macros.Length > itemsPerPage) {
        paginationY := scrollY + 470
        
        pageInfo := win.Add("Text", "x25 y" paginationY " w300 c" COLORS.textDim, 
            "Page " currentPage " of " totalPages " (" macros.Length " total)")
        pageInfo.SetFont("s9")
        win.__cards.Push(pageInfo)
        
        if (currentPage > 1) {
            prevBtn := win.Add("Button", "x335 y" (paginationY - 5) " w90 h35 Background" COLORS.accentHover, "← Previous")
            prevBtn.SetFont("s9")
            prevBtn.OnEvent("Click", (*) => ChangePage(win, -1))
            win.__cards.Push(prevBtn)
        }
        
        if (currentPage < totalPages) {
            nextBtn := win.Add("Button", "x635 y" (paginationY - 5) " w90 h35 Background" COLORS.accentHover, "Next →")
            nextBtn.SetFont("s9")
            nextBtn.OnEvent("Click", (*) => ChangePage(win, 1))
            win.__cards.Push(nextBtn)
        }
    }
}

CreateFullWidthCard(win, item, x, y, w, h) {
    global COLORS
    
    card := win.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    win.__cards.Push(card)
    
    iconPath := GetMacroIcon(item.path)
    hasIcon := false
    
    if (iconPath && FileExist(iconPath)) {
        try {
            pic := win.Add("Picture", "x" (x + 20) " y" (y + 15) " w80 h80 BackgroundTrans", iconPath)
            win.__cards.Push(pic)
            hasIcon := true
        } catch {
        }
    }
    
    if (!hasIcon) {
        initial := SubStr(item.info.Title, 1, 1)
        iconColor := GetCategoryColor(item.info.Title)
        badge := win.Add("Text", "x" (x + 20) " y" (y + 15) " w80 h80 Background" iconColor " Center", initial)
        badge.SetFont("s32 bold c" COLORS.text)
        win.__cards.Push(badge)
    }
    
    titleCtrl := win.Add("Text", "x" (x + 120) " y" (y + 20) " w420 h100 c" COLORS.text " BackgroundTrans", item.info.Title)
    titleCtrl.SetFont("s13 bold")
    win.__cards.Push(titleCtrl)
    
    creatorCtrl := win.Add("Text", "x" (x + 120) " y" (y + 50) " w420 c" COLORS.textDim " BackgroundTrans", "by " item.info.Creator)
    creatorCtrl.SetFont("s10")
    win.__cards.Push(creatorCtrl)
    
    versionCtrl := win.Add("Text", "x" (x + 120) " y" (y + 75) " w60 h22 Background" COLORS.accentAlt " c" COLORS.text " Center", "v" item.info.Version)
    versionCtrl.SetFont("s9 bold")
    win.__cards.Push(versionCtrl)
    
    currentPath := item.path
    runBtn := win.Add("Button", "x" (x + w - 110) " y" (y + 20) " w100 h35 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s11 bold")
    runBtn.OnEvent("Click", (*) => RunMacro(currentPath))
    win.__cards.Push(runBtn)
    
    if (Trim(item.info.Links) != "") {
        currentLinks := item.info.Links
        linksBtn := win.Add("Button", "x" (x + w - 110) " y" (y + 65) " w100 h30 Background" COLORS.accentAlt, "🔗 Links")
        linksBtn.SetFont("s10")
        linksBtn.OnEvent("Click", (*) => OpenLinks(currentLinks))
        win.__cards.Push(linksBtn)
    }
}

CreateGridCard(win, item, x, y, w, h) {
    global COLORS
    
    card := win.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    win.__cards.Push(card)
    
    iconPath := GetMacroIcon(item.path)
    hasIcon := false
    
    if (iconPath && FileExist(iconPath)) {
        try {
            pic := win.Add("Picture", "x" (x + 15) " y" (y + 15) " w60 h60 BackgroundTrans", iconPath)
            win.__cards.Push(pic)
            hasIcon := true
        } catch {
        }
    }
    
    if (!hasIcon) {
        initial := SubStr(item.info.Title, 1, 1)
        iconColor := GetCategoryColor(item.info.Title)
        badge := win.Add("Text", "x" (x + 15) " y" (y + 15) " w60 h60 Background" iconColor " Center", initial)
        badge.SetFont("s24 bold c" COLORS.text)
        win.__cards.Push(badge)
    }
    
    titleCtrl := win.Add("Text", "x" (x + 90) " y" (y + 15) " w" (w - 190) " h" (h + 50) " c" COLORS.text " BackgroundTrans", item.info.Title)
    titleCtrl.SetFont("s11 bold")
    win.__cards.Push(titleCtrl)
    
    creatorCtrl := win.Add("Text", "x" (x + 90) " y" (y + 40) " w" (w - 190) " c" COLORS.textDim " BackgroundTrans", "by " item.info.Creator)
    creatorCtrl.SetFont("s9")
    win.__cards.Push(creatorCtrl)
    
    versionCtrl := win.Add("Text", "x" (x + 90) " y" (y + 65) " w50 h20 Background" COLORS.accentAlt " c" COLORS.text " Center", "v" item.info.Version)
    versionCtrl.SetFont("s8 bold")
    win.__cards.Push(versionCtrl)
    
    currentPath := item.path
    runBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 15) " w80 h30 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s10 bold")
    runBtn.OnEvent("Click", (*) => RunMacro(currentPath))
    win.__cards.Push(runBtn)
    
    if (Trim(item.info.Links) != "") {
        currentLinks := item.info.Links
        linksBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 55) " w80 h25 Background" COLORS.accentAlt, "🔗 Links")
        linksBtn.SetFont("s9")
        linksBtn.OnEvent("Click", (*) => OpenLinks(currentLinks))
        win.__cards.Push(linksBtn)
    }
}

ChangePage(win, direction) {
    win.__currentPage := win.__currentPage + direction
    
    totalPages := Ceil(win.__data.Length / win.__itemsPerPage)
    
    if (win.__currentPage < 1) {
        win.__currentPage := 1
    }
    if (win.__currentPage > totalPages) {
        win.__currentPage := totalPages
    }
    
    RenderCards(win)
}

GetMacroIcon(macroPath) {
    global BASE_DIR, ICON_DIR
    
    try {
        SplitPath macroPath, , &macroDir
        SplitPath macroDir, &macroName
        
        extensions := ["png", "ico", "jpg", "jpeg"]
        
        for ext in extensions {
            iconPath := ICON_DIR "\" macroName "." ext
            if FileExist(iconPath) {
                return iconPath
            }
        }
        
        for ext in extensions {
            iconPath := macroDir "\icon." ext
            if FileExist(iconPath) {
                return iconPath
            }
        }
        
        SplitPath macroDir, , &gameDir
        for ext in extensions {
            iconPath := gameDir "\" macroName "." ext
            if FileExist(iconPath) {
                return iconPath
            }
        }
    }
    
    return ""
}

GetMacrosWithInfo(category) {
    global BASE_DIR
    out := []
    base := BASE_DIR "\" category
    
    if !DirExist(base) {
        return out
    }
    
    try {
        Loop Files, base "\*", "D" {
            subFolder := A_LoopFilePath
            mainFile := subFolder "\Main.ahk"
            
            if FileExist(mainFile) {
                try {
                    info := ReadMacroInfo(subFolder)
                    out.Push({
                        path: mainFile,
                        info: info
                    })
                }
            }
        }
    }
    
    if (out.Length = 0) {
        mainFile := base "\Main.ahk"
        if FileExist(mainFile) {
            try {
                info := ReadMacroInfo(base)
                out.Push({
                    path: mainFile,
                    info: info
                })
            }
        }
    }
    
    return out
}

ReadMacroInfo(macroDir) {
    info := {
        Title: "",
        Creator: "",
        Version: "",
        Links: ""
    }
    
    try {
        SplitPath macroDir, &folder
        info.Title := folder
    }
    
    ini := macroDir "\info.ini"
    if !FileExist(ini) {
        return info
    }
    
    try {
        txt := SecureFileRead(ini)
        if !txt
            txt := FileRead(ini, "UTF-8")
    } catch {
        return info
    }
    
    for line in StrSplit(txt, "`n") {
        line := Trim(StrReplace(line, "`r"))
        
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#") {
            continue
        }
        
        if !InStr(line, "=") {
            continue
        }
        
        parts := StrSplit(line, "=", , 2)
        if (parts.Length < 2) {
            continue
        }
        
        k := StrLower(Trim(parts[1]))
        v := Trim(parts[2])
        
        switch k {
            case "title":
                info.Title := v
            case "creator":
                info.Creator := v
            case "version":
                info.Version := v
            case "links":
                info.Links := v
        }
    }
    
    if (info.Version = "") {
        info.Version := "1.0"
    }
    
    return info
}

OpenLinks(links) {
    if !links || Trim(links) = "" {
        return
    }
    
    try {
        for url in StrSplit(links, "|") {
            url := Trim(url)
            if (url != "") {
                SafeOpenURL(url)
            }
        }
    } catch as err {
        MsgBox "Failed to open link: " err.Message, "Error", "Icon!"
    }
}

ShowChangelog(*) {
    global MANIFEST_URL
    
    tmpManifest := A_Temp "\manifest.json"
    
    if !SafeDownload(MANIFEST_URL, tmpManifest) {
        MsgBox "Couldn't download manifest.json`n`nCheck your internet connection.", "Error", "Icon!"
        return
    }
    
    json := ""
    try {
        json := FileRead(tmpManifest, "UTF-8")
    } catch {
        MsgBox "Failed to read manifest file.", "Error", "Icon!"
        return
    }
    
    manifest := ParseManifest(json)
    if !manifest {
        MsgBox "Failed to parse manifest data.", "Error", "Icon!"
        return
    }
    
    text := ""
    if (manifest.changelog.Length > 0) {
        for line in manifest.changelog {
            text .= "• " line "`n"
        }
    }
    
    if (text = "") {
        text := "(No changelog available)"
    }
    
    MsgBox "Version: " manifest.version "`n`n" text, "Changelog", "Iconi"
}

TryDirMove(src, dst, overwrite := true, retries := 10) {
    loop retries {
        try {
            DirMove src, dst, overwrite ? 1 : 0
            return true
        } catch as err {
            Sleep 250
            if (A_Index = retries)
                throw Error("DirMove failed:`n" err.Message "`n`nFrom:`n" src "`nTo:`n" dst)
        }
    }
    return false
}

TryFileCopy(src, dst, overwrite := true, retries := 10) {
    loop retries {
        try {
            FileCopy src, dst, overwrite ? 1 : 0
            return true
        } catch as err {
            Sleep 250
            if (A_Index = retries)
                throw Error("FileCopy failed:`n" err.Message "`n`nFrom:`n" src "`nTo:`n" dst)
        }
    }
    return false
}

ShowUpdateFail(context, err, extra := "") {
    msg := "❌ Failed to install macro updates`n`n"
        . "Step: " context "`n"
        . "Error: " err.Message "`n`n"
        . "Extra: " extra "`n`n"
        . "A_LastError: " A_LastError "`n"
        . "A_WorkingDir: " A_WorkingDir "`n"
        . "AppData: " A_AppData

    MsgBox msg, "AHK vault - Update Failed", "Icon! 0x10"
}

IsValidZip(path) {
    try {
        if !FileExist(path)
            return false
        if (FileGetSize(path) < 100)
            return false

        f := FileOpen(path, "r")
        sig := f.Read(2)
        f.Close()

        return (sig = "PK")
    } catch {
        return false
    }
}

; ================= AUTHENTICATION FUNCTIONS =================

LoadSecureConfig() {
    global SECURE_CONFIG_FILE, MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS
    
    ; Always fetch master key from manifest
    FetchMasterKeyFromManifest()
    
    if !FileExist(SECURE_CONFIG_FILE) {
        InitializeAuthConfig()
        return
    }
    
    try {
        encrypted := FileRead(SECURE_CONFIG_FILE, "UTF-8")
        decrypted := DecryptConfig(encrypted)
        
        ; Don't load master key from file - always use manifest value
        if RegExMatch(decrypted, '"webhook"\s*:\s*"([^"]+)"', &m2)
            DISCORD_WEBHOOK := m2[1]
        if RegExMatch(decrypted, '"admin_pass"\s*:\s*"([^"]+)"', &m3)
            ADMIN_PASS := m3[1]
        
        if (DISCORD_WEBHOOK = "") {
            try {
                DISCORD_WEBHOOK := GetWebhookFromManifest()
                if (DISCORD_WEBHOOK != "")
                    SaveAuthConfig()
            } catch {
            }
        }
        
        if (MASTER_KEY = "" || DISCORD_WEBHOOK = "" || ADMIN_PASS = "") {
            InitializeAuthConfig()
        }
    } catch {
        InitializeAuthConfig()
    }
}

FetchMasterKeyFromManifest() {
    global MASTER_KEY, MANIFEST_URL
    
    try {
        tmp := A_Temp "\manifest_config.json"
        if SafeDownload(MANIFEST_URL, tmp, 20000) {
            json := FileRead(tmp, "UTF-8")
            if RegExMatch(json, '"master_key"\s*:\s*"([^"]+)"', &m) {
                MASTER_KEY := m[1]
                return true
            }
        }
    } catch {
    }
    
    ; If we can't fetch, generate temporary one (will fail auth but won't crash)
    if (MASTER_KEY = "") {
        MASTER_KEY := GenerateRandomKey(32)
        return false
    }
    
    return false
}

InitializeAuthConfig() {
    global MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS, SECURE_CONFIG_FILE
    
    ; Fetch master key from manifest
    if (MASTER_KEY = "")
        FetchMasterKeyFromManifest()
    
    ADMIN_PASS := GenerateRandomKey(16)
    
    ; Get webhook from manifest
    if (DISCORD_WEBHOOK = "") {
        try {
            DISCORD_WEBHOOK := GetWebhookFromManifest()
        } catch {
            DISCORD_WEBHOOK := ""
        }
    }
    
    SaveAuthConfig()
    NotifyInitialSetup()
}

SaveAuthConfig() {
    global SECURE_CONFIG_FILE, MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS
    
    try {
        ; Only save webhook and admin_pass, not master_key
        json := '{"webhook":"' JsonEscape(DISCORD_WEBHOOK) '",'
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

GenerateRandomKey(length := 32) {
    chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
    key := ""
    
    loop length {
        idx := Random(1, StrLen(chars))
        key .= SubStr(chars, idx, 1)
    }
    
    return key
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
        hwid := A_ComputerName . A_UserName
    }
    
    hash := 0
    loop parse hwid
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    
    return hash
}

NotifyStartupCredentials() {
    global DISCORD_WEBHOOK, MASTER_KEY, ADMIN_PASS
    
    if (DISCORD_WEBHOOK = "")
        return
    
    ; Send full credentials only if admin
    if IsAdminDiscordId() {
        ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        hwid := GetHardwareId()
        did := ReadDiscordId()
        
        msg := "📋 AHK VAULT - CURRENT CREDENTIALS (Admin Login)"
            . "`n`n**Master Key:** ||" MASTER_KEY "||"
            . "`n**Admin Password:** ||" ADMIN_PASS "||"
            . "`n**Time:** " ts
            . "`n**PC:** " A_ComputerName
            . "`n**User:** " A_UserName
            . "`n**Discord ID:** " did
            . "`n**HWID:** " hwid
        
        DiscordWebhookPost(DISCORD_WEBHOOK, msg)
    } else {
        ; Send basic notification for non-admins
        NotifyNonAdminStartup()
    }
}

NotifyInitialSetup() {
    global DISCORD_WEBHOOK, MASTER_KEY, ADMIN_PASS
    
    if (DISCORD_WEBHOOK = "")
        return
    
    ; Only send credentials if current user is an admin
    if !IsAdminDiscordId()
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "🎉 AHK VAULT - INITIAL SETUP (Admin)"
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

NotifyNonAdminStartup() {
    global DISCORD_WEBHOOK
    
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "👤 AHK VAULT - User Startup (Non-Admin)"
        . "`n`n**Time:** " ts
        . "`n**PC:** " A_ComputerName
        . "`n**User:** " A_UserName
        . "`n**Discord ID:** " did
        . "`n**HWID:** " hwid
    
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

GetWebhookFromManifest() {
    global MANIFEST_URL
    
    tmp := A_Temp "\manifest_webhook.json"
    if !SafeDownload(MANIFEST_URL, tmp, 20000)
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
    global DISCORD_BAN_FILE, ADMIN_DISCORD_FILE, DISCORD_WEBHOOK
    
    ; Fetch master key from manifest
    FetchMasterKeyFromManifest()
    
    tmp := A_Temp "\manifest.json"
    if !SafeDownload(MANIFEST_URL, tmp, 30000)
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
        OverwriteListFile(HWID_BAN_FILE, lists.banned_hwids)

    }
    
    mf := ParseManifestForCredsAndLauncher(json)
    if !IsObject(mf)
        return false
    
    user := Trim(mf.cred_user)
    hash := Trim(mf.cred_hash)
    password := Trim(mf.cred_password)
    webhook := Trim(mf.webhook)
    
    if (webhook != "" && DISCORD_WEBHOOK = "") {
        DISCORD_WEBHOOK := webhook
        SaveAuthConfig()
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
    
    return true
}

ParseManifestForCredsAndLauncher(json) {
    obj := { cred_user: "", cred_hash: "", cred_password: "", webhook: "" }
    try {
        if RegExMatch(json, '"cred_user"\s*:\s*"([^"]+)"', &m1)
            obj.cred_user := m1[1]
        if RegExMatch(json, '"cred_hash"\s*:\s*"([^"]+)"', &m2)
            obj.cred_hash := m2[1]
        if RegExMatch(json, '"cred_password"\s*:\s*"([^"]+)"', &m3)
            obj.cred_password := m3[1]
        if RegExMatch(json, '"webhook"\s*:\s*"([^"]+)"', &m5)
            obj.webhook := m5[1]
    } catch {
        return false
    }
    return obj
}

ParseManifestLists(json) {
    obj := { banned: [], admins: [], banned_hwids: [] }

    ; banned_discord_ids
    if RegExMatch(json, '(?s)"banned_discord_ids"\s*:\s*\[(.*?)\]', &m1) {
        inner := m1[1]
        pos := 1
        while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem, pos)) {
            obj.banned.Push(mItem[1])
            pos += StrLen(mItem[0])
        }
    }

    ; admin_discord_ids
    if RegExMatch(json, '(?s)"admin_discord_ids"\s*:\s*\[(.*?)\]', &m2) {
        inner := m2[1]
        pos := 1
        while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem2, pos)) {
            obj.admins.Push(mItem2[1])
            pos += StrLen(mItem2[0])
        }
    }

    ; banned_hwids (strings/numbers in quotes)
    if RegExMatch(json, '(?s)"banned_hwids"\s*:\s*\[(.*?)\]', &m3) {
        inner := m3[1]
        pos := 1
        while (pos := RegExMatch(inner, '"([^"]+)"', &mItem3, pos)) {
            v := Trim(mItem3[1])
            if (v != "")
                obj.banned_hwids.Push(v)
            pos += StrLen(mItem3[0])
        }
    }

    return obj
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
        resp := WorkerPost("/check-ban", body)
        
if RegExMatch(resp, '"banned"\s*:\s*true') {
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

ClearMachineBan() {
    global MACHINE_BAN_FILE
    try {
        if FileExist(MACHINE_BAN_FILE)
            FileDelete MACHINE_BAN_FILE
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

CheckSession() {
    global SESSION_FILE, CRED_FILE
    if IsHwidBanned()
    return false

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
    if (sessionMachine != GetHardwareId())
        return false
    
    ; Check ban status
    if IsDiscordBanned()
        return false
    
    ; Validate credentials exist
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
    
    return true
}

CreateSession(loginUser := "", role := "user") {
    global SESSION_FILE, SESSION_LOG_FILE, CRED_FILE
    try {
        t := A_Now
        mh := GetHardwareId()
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

StartSessionWatchdog() {
    SetTimer(CheckCredHashTicker, 10000)
    SetTimer(CheckBanStatusPeriodic, 10000)
    SetTimer(RefreshMasterKeyPeriodic, 10000)
}

RefreshMasterKeyPeriodic() {
    FetchMasterKeyFromManifest()
}

CheckCredHashTicker() {
    global SESSION_FILE
    if !FileExist(SESSION_FILE)
        return
    
    RefreshManifestAndLauncherBeforeLogin()
}

CheckBanStatusPeriodic() {
    if !ValidateNotBanned() {
        try DestroyLoginGui()
        ShowBanMessage()
        ExitApp
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
        CheckForUpdatesPrompt()
        CreateMainGui()
        return
    }
    
    ; ADMIN LOGIN
    if (password = ADMIN_PASS && IsAdminDiscordId()) {
        attemptCount := 0
        CreateSession(username, "admin")
        SendDiscordLogin("admin", username)
        StartSessionWatchdog()
        DestroyLoginGui()
        CheckForUpdatesPrompt()
        CreateMainGui()
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
            CheckForUpdatesPrompt()
            CreateMainGui()
            return
        }
        
        ; Fallback: check hash
        if (storedHash != "") {
            enteredHash := HashPassword(password)
            if (StrLower(username) = StrLower(storedUser) && enteredHash = storedHash) {
                attemptCount := 0
                CreateSession(storedUser, "user")
                SendDiscordLogin("user", storedUser)
                StartSessionWatchdog()
                DestroyLoginGui()
                CheckForUpdatesPrompt()
                CreateMainGui()
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

IsAdminDiscordId() {
    global ADMIN_DISCORD_FILE
    did := StrLower(Trim(ReadDiscordId()))
    if (did = "")
        return false
    
    if !FileExist(ADMIN_DISCORD_FILE)
        return false
    
    try {
        txt := FileRead(ADMIN_DISCORD_FILE, "UTF-8")
        for line in StrSplit(txt, "`n") {
            if (StrLower(Trim(line)) = did)
                return true
        }
    }
    
    return false
}
AddBannedHwid(hwid) {
    global HWID_BAN_FILE
    hwid := Trim(hwid)
    if (hwid = "")
        return
    ids := GetLinesFromFile(HWID_BAN_FILE)
    for x in ids
        if (Trim(x) = hwid)
            return
    ids.Push(hwid)
    WriteLinesToFile(HWID_BAN_FILE, ids)
}

RemoveBannedHwid(hwid) {
    global HWID_BAN_FILE
    ids := []
    for x in GetLinesFromFile(HWID_BAN_FILE)
        if (Trim(x) != Trim(hwid))
            ids.Push(x)
    WriteLinesToFile(HWID_BAN_FILE, ids)
}

IsHwidBanned() {
    global HWID_BAN_FILE
    if !FileExist(HWID_BAN_FILE)
        return false
    hwid := GetHardwareId()
    for x in GetLinesFromFile(HWID_BAN_FILE)
        if (Trim(x) = hwid)
            return true
    return false
}
LogoutNow(*) {
    global SESSION_FILE, mainGui

    SetTimer(CheckCredHashTicker, 0)
    SetTimer(CheckBanStatusPeriodic, 0)
    SetTimer(RefreshMasterKeyPeriodic, 0)

    try FileDelete SESSION_FILE
    try mainGui.Destroy()

    CreateLoginGui()
}
OnBanHwid(hwidEdit, bannedHwidLbl, *) {
    hwid := RegExReplace(Trim(hwidEdit.Value), "[^\d]") ; normalize
    if (hwid = "") {
        MsgBox "Enter a valid HWID (numbers only).", "AHK VAULT - Admin", "Icon!"
        return
    }

    try {
        resp := WorkerPost("/ban-hwid", '{"hwid":"' JsonEscape(hwid) '"}')
        ResyncListsFromManifestNow()
        RefreshBannedHwidLabel(bannedHwidLbl)
        MsgBox "✅ Globally BANNED HWID: " hwid, "AHK VAULT - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to ban HWID globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

OnUnbanHwid(hwidEdit, bannedHwidLbl, *) {
    hwid := RegExReplace(Trim(hwidEdit.Value), "[^\d]") ; normalize
    if (hwid = "") {
        MsgBox "Enter a valid HWID (numbers only).", "AHK VAULT - Admin", "Icon!"
        return
    }

    try {
        resp := WorkerPost("/unban-hwid", '{"hwid":"' JsonEscape(hwid) '"}')
        ResyncListsFromManifestNow()
        RefreshBannedHwidLabel(bannedHwidLbl)
        ClearMachineBan()
        MsgBox "✅ Globally UNBANNED HWID: " hwid, "AHK VAULT - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to unban HWID globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

; ================= UPDATED FUNCTIONS WITH WEBHOOK CALLS =================

; UPDATED: OnBanDiscordId - now sends webhook notification
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
        
        ; NEW: Send webhook notification
        SendDiscordBan(did, "admin_panel")
        
        MsgBox "✅ Globally BANNED: " did, "AHK VAULT - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to ban globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

; UPDATED: OnUnbanDiscordId - now sends webhook notification
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
            ; NEW: Send webhook notification
            SendDiscordUnban(did)
            
            MsgBox "✅ Globally UNBANNED: " did, "AHK VAULT - Admin", "Iconi"
            ClearMachineBan()
        }
    } catch as err {
        MsgBox "❌ Failed to unban globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

; UPDATED: OnAddAdminDiscord - now sends webhook notification
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
        
        ; NEW: Send webhook notification
        SendDiscordAdminAdd(did)
        
        MsgBox "✅ Globally added admin: " did, "AHK VAULT - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to add admin globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

; UPDATED: OnRemoveAdminDiscord - now sends webhook notification
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
        
        ; NEW: Send webhook notification
        SendDiscordAdminRemove(did)
        
        MsgBox "✅ Globally removed admin: " did, "AHK VAULT - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to remove admin globally:`n" err.Message, "AHK VAULT - Admin", "Icon!"
    }
}

; UPDATED: CompleteUninstall - now sends webhook notification
CompleteUninstall(*) {
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR, VERSION_FILE, MACHINE_KEY
    global CRED_FILE, SESSION_FILE, DISCORD_ID_FILE, DISCORD_BAN_FILE
    global ADMIN_DISCORD_FILE, SESSION_LOG_FILE, MACHINE_BAN_FILE
    global HWID_BINDING_FILE, LAST_CRED_HASH_FILE, SECURE_CONFIG_FILE
    global ENCRYPTED_KEY_FILE, MASTER_KEY_ROTATION_FILE
    
    choice := MsgBox(
        "⚠️ WARNING ⚠️`n`n"
        . "This will permanently delete:`n"
        . "• All downloaded macros`n"
        . "• All icons and resources`n"
        . "• All encrypted data`n"
        . "• Version information`n"
        . "• Security keys and vault data`n"
        . "• All login credentials and sessions`n"
        . "• Discord ID and ban records`n`n"
        . "This action CANNOT be undone!`n`n"
        . "Are you sure you want to completely uninstall?",
        "Complete Uninstall",
        "YesNo Icon! Default2"
    )
    
    if (choice = "No")
        return
    
    choice2 := MsgBox(
        "⚠️ FINAL WARNING ⚠️`n`n"
        . "This will permanently delete:`n"
        . "• All downloaded macros`n"
        . "• All encrypted files`n"
        . "• All icons and resources`n"
        . "• All version information`n"
        . "• Machine registration keys`n"
        . "• All authentication data`n"
        . "• All session history`n`n"
        . "This cannot be undone!`n`n"
        . "Are you ABSOLUTELY sure?",
        "Confirm Complete Removal",
        "YesNo Icon! Default2"
    )
    
    if (choice2 = "No")
        return
    
    ; NEW: Send webhook notification BEFORE uninstalling
    SendDiscordUninstall()
    
    try {
        ; Clear authentication files first
        try {
            if FileExist(CRED_FILE) {
                RunWait 'attrib -h -s -r "' CRED_FILE '"', , "Hide"
                FileDelete CRED_FILE
            }
        }
        
        try {
            if FileExist(SESSION_FILE) {
                RunWait 'attrib -h -s -r "' SESSION_FILE '"', , "Hide"
                FileDelete SESSION_FILE
            }
        }
        
        try {
            if FileExist(DISCORD_ID_FILE) {
                RunWait 'attrib -h -s -r "' DISCORD_ID_FILE '"', , "Hide"
                FileDelete DISCORD_ID_FILE
            }
        }
        
        try {
            if FileExist(DISCORD_BAN_FILE) {
                RunWait 'attrib -h -s -r "' DISCORD_BAN_FILE '"', , "Hide"
                FileDelete DISCORD_BAN_FILE
            }
        }
        
        try {
            if FileExist(ADMIN_DISCORD_FILE) {
                RunWait 'attrib -h -s -r "' ADMIN_DISCORD_FILE '"', , "Hide"
                FileDelete ADMIN_DISCORD_FILE
            }
        }
        
        try {
            if FileExist(SESSION_LOG_FILE) {
                RunWait 'attrib -h -s -r "' SESSION_LOG_FILE '"', , "Hide"
                FileDelete SESSION_LOG_FILE
            }
        }
        
        try {
            if FileExist(MACHINE_BAN_FILE) {
                RunWait 'attrib -h -s -r "' MACHINE_BAN_FILE '"', , "Hide"
                FileDelete MACHINE_BAN_FILE
            }
        }
        
        try {
            if FileExist(HWID_BINDING_FILE) {
                RunWait 'attrib -h -s -r "' HWID_BINDING_FILE '"', , "Hide"
                FileDelete HWID_BINDING_FILE
            }
        }
        
        try {
            if FileExist(LAST_CRED_HASH_FILE) {
                RunWait 'attrib -h -s -r "' LAST_CRED_HASH_FILE '"', , "Hide"
                FileDelete LAST_CRED_HASH_FILE
            }
        }
        
        try {
            if FileExist(SECURE_CONFIG_FILE) {
                RunWait 'attrib -h -s -r "' SECURE_CONFIG_FILE '"', , "Hide"
                FileDelete SECURE_CONFIG_FILE
            }
        }
        
        try {
            if FileExist(ENCRYPTED_KEY_FILE) {
                RunWait 'attrib -h -s -r "' ENCRYPTED_KEY_FILE '"', , "Hide"
                FileDelete ENCRYPTED_KEY_FILE
            }
        }
        
        try {
            if FileExist(MASTER_KEY_ROTATION_FILE) {
                RunWait 'attrib -h -s -r "' MASTER_KEY_ROTATION_FILE '"', , "Hide"
                FileDelete MASTER_KEY_ROTATION_FILE
            }
        }
        
        ; Remove version file
        if FileExist(VERSION_FILE) {
            RunWait 'attrib -h -s -r "' VERSION_FILE '"', , "Hide"
            FileDelete VERSION_FILE
        }
        
        ; Remove directories
        if DirExist(BASE_DIR) {
            RunWait 'attrib -h -s -r "' BASE_DIR '" /s /d', , "Hide"
            DirDelete BASE_DIR, true
        }
        
        if DirExist(ICON_DIR) {
            RunWait 'attrib -h -s -r "' ICON_DIR '" /s /d', , "Hide"
            DirDelete ICON_DIR, true
        }
        
        if DirExist(SECURE_VAULT) {
            RunWait 'attrib -h -s -r "' SECURE_VAULT '" /s /d', , "Hide"
            DirDelete SECURE_VAULT, true
        }
        
        if DirExist(APP_DIR) {
            RunWait 'attrib -h -s -r "' APP_DIR '"', , "Hide"
            DirDelete APP_DIR, true
        }
        
        ; Clear registry entries (machine key rotation data)
        regPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo"
        try RegDelete regPath, "MachineGUID"
        try RegDelete regPath, "KeyHistory"
        try RegDelete regPath, "LastRotation"
        
        ; Clear lockout file if exists
        try {
            if FileExist(A_Temp "\.lockout") {
                FileDelete A_Temp "\.lockout"
            }
        }
        
        MsgBox(
            "✅ Complete uninstall successful!`n`n"
            . "Removed:`n"
            . "• All macros and encrypted data`n"
            . "• All icons and resources`n"
            . "• All authentication files`n"
            . "• All session history`n"
            . "• All registry keys`n"
            . "• All ban records`n`n"
            . "The launcher will now close.",
            "Uninstall Complete",
            "Iconi"
        )
        
        ExitApp
        
    } catch as err {
        MsgBox(
            "❌ Failed to delete some files:`n`n"
            . err.Message "`n`n"
            . "Some files may require manual deletion.`n"
            . "Location: " SECURE_VAULT,
            "Uninstall Error",
            "Icon!"
        )
    }
}

; UPDATED: CheckLockout - now sends webhook notification for master key usage
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
                ? (FileDelete(LOCKOUT_FILE), 
                   SendDiscordMasterKeyUsed("unlock_account"),
                   lockGui.Destroy(), 
                   MsgBox("✅ Lockout removed.", "AHK VAULT", "Iconi"))
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

; UPDATED: AdminPanel - now sends webhook notification for master key usage
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
        
        ; NEW: Send master key usage notification
        SendDiscordMasterKeyUsed("admin_panel_access")
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

; UPDATED: OnChangeMasterKey - now functional and sends webhook notification
OnChangeMasterKey(*) {
    global MASTER_KEY
    
    choice := MsgBox(
        "⚠️ Change Master Key?`n`n"
        . "This will update the master key in manifest.json`n"
        . "All clients will auto-update within 10 minutes`n`n"
        . "Continue?",
        "AHK VAULT - Change Master Key",
        "YesNo Icon! 0x30"
    )
    
    if (choice = "No")
        return
    
    newKey := InputBox(
        "Enter NEW Master Key:`n`n"
        . "⚠️ Save this key securely!`n"
        . "⚠️ All users will need this key to access admin features",
        "AHK VAULT - New Master Key",
        "Password w500 h200"
    )
    
    if (newKey.Result != "OK")
        return
    
    newMasterKey := Trim(newKey.Value)
    
    if (newMasterKey = "" || StrLen(newMasterKey) < 8) {
        MsgBox "Master key must be at least 8 characters long.", "AHK VAULT - Invalid", "Icon! 0x30"
        return
    }
    
    try {
        body := '{"master_key":"' JsonEscape(newMasterKey) '"}'
        WorkerPost("/master-key/set", body)
        
        oldKey := MASTER_KEY
        MASTER_KEY := newMasterKey
        
        ; NEW: Send master key change notification
        SendDiscordMasterKeyChanged(ReadDiscordId())
        
        MsgBox(
            "✅ Master Key Updated Successfully!`n`n"
            . "New Master Key: " newMasterKey "`n`n"
            . "⚠️ IMPORTANT:`n"
            . "• This has been updated in manifest.json`n"
            . "• All clients will auto-update within 10 minutes`n"
            . "• Save this key securely!`n"
            . "• Old key: " oldKey,
            "AHK VAULT - Success",
            "Iconi"
        )
        
        A_Clipboard := newMasterKey
        
    } catch as err {
        MsgBox "❌ Failed to change master key:`n" err.Message, "AHK VAULT - Error", "Icon! 0x10"
    }
}

; UPDATED: RunMacro - now sends webhook notification (optional - only for admins)
RunMacro(path) {
    if !FileExist(path) {
        MsgBox "Macro not found:`n" path, "Error", "Icon!"
        return
    }
    
    try {
        decryptedPath := DecryptMacroForExecution(path)
        
        if !decryptedPath || !FileExist(decryptedPath) {
            decryptedPath := path
        }
        
        ; NEW: Send webhook notification (only for admins to avoid spam)
        try {
            SplitPath decryptedPath, &macroFile
            SendDiscordMacroRun(macroFile)
        }
        
        SplitPath decryptedPath, , &dir
        Run '"' A_AhkPath '" "' decryptedPath '"', dir
    } catch as err {
        MsgBox "Failed to run macro: " err.Message, "Error", "Icon!"
    }
}

; ================= ENHANCED WEBHOOK NOTIFICATIONS =================

; Send ban notification to Discord
SendDiscordBan(discordId, reason := "manual") {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    
    msg := "🚫 **USER BANNED**"
        . "`n`n**Discord ID:** " discordId
        . "`n**Reason:** " reason
        . "`n**PC Name:** " A_ComputerName
        . "`n**Windows User:** " A_UserName
        . "`n**HWID:** " hwid
        . "`n**Time:** " ts
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

; Send unban notification to Discord
SendDiscordUnban(discordId) {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    
    msg := "✅ **USER UNBANNED**"
        . "`n`n**Discord ID:** " discordId
        . "`n**PC Name:** " A_ComputerName
        . "`n**Windows User:** " A_UserName
        . "`n**HWID:** " hwid
        . "`n**Time:** " ts
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

; Send uninstall notification to Discord
SendDiscordUninstall() {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "🗑️ **LAUNCHER UNINSTALLED**"
        . "`n`n**Discord ID:** " did
        . "`n**PC Name:** " A_ComputerName
        . "`n**Windows User:** " A_UserName
        . "`n**HWID:** " hwid
        . "`n**Time:** " ts
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

; Send admin add notification to Discord
SendDiscordAdminAdd(discordId) {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    currentAdmin := ReadDiscordId()
    
    msg := "👑 **ADMIN ADDED**"
        . "`n`n**New Admin ID:** " discordId
        . "`n**Added by:** " currentAdmin
        . "`n**PC Name:** " A_ComputerName
        . "`n**Time:** " ts
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

; Send admin remove notification to Discord
SendDiscordAdminRemove(discordId) {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    currentAdmin := ReadDiscordId()
    
    msg := "⚠️ **ADMIN REMOVED**"
        . "`n`n**Removed Admin ID:** " discordId
        . "`n**Removed by:** " currentAdmin
        . "`n**PC Name:** " A_ComputerName
        . "`n**Time:** " ts
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

; Send macro run notification to Discord (optional - can be spammy)
SendDiscordMacroRun(macroName) {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return
    
    ; Only send for admins to avoid spam
    if !IsAdminDiscordId()
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    did := ReadDiscordId()
    
    msg := "▶️ **MACRO EXECUTED**"
        . "`n`n**Macro:** " macroName
        . "`n**Discord ID:** " did
        . "`n**PC Name:** " A_ComputerName
        . "`n**Time:** " ts
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

; Send master key usage notification to Discord
SendDiscordMasterKeyUsed(action := "login") {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "🔑 **MASTER KEY USED**"
        . "`n`n**Action:** " action
        . "`n**Discord ID:** " did
        . "`n**PC Name:** " A_ComputerName
        . "`n**Windows User:** " A_UserName
        . "`n**HWID:** " hwid
        . "`n**Time:** " ts
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

; Send master key change notification to Discord
SendDiscordMasterKeyChanged(changedBy := "") {
    global DISCORD_WEBHOOK, MASTER_KEY
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "⚠️ **MASTER KEY CHANGED**"
        . "`n`n**Changed by:** " (changedBy != "" ? changedBy : did)
        . "`n**New Master Key:** ||" MASTER_KEY "||"
        . "`n**PC Name:** " A_ComputerName
        . "`n**Windows User:** " A_UserName
        . "`n**HWID:** " hwid
        . "`n**Time:** " ts
        . "`n`n⚠️ **All users will need to use this new key!**"
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}
