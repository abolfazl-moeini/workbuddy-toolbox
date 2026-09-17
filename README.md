# WorkBuddy Toolbox (`wb`)

> **TL;DR:** WorkBuddy AI hides your local chat history when you switch accounts or log out (because conversations in SQLite are partitioned by `userId`).  
> **`wb merge`** instantly unhides and brings all your chat sessions into your active account.  
> **`wb switch <name>`** lets you switch between multiple accounts in one command without opening the browser.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-lightgrey.svg)]()
[![Shell](https://img.shields.io/badge/Shell-Bash-black.svg)]()

---

## ⚡ Quick Start (TL;DR)

### 1. Install in 10 seconds
```bash
git clone https://github.com/abolfazl-moeini/workbuddy-toolbox.git
cd workbuddy-toolbox
chmod +x wb-toolbox.sh && ./wb-toolbox.sh install
```
*(Installs the `wb` command globally in your PATH).*

### 2. Disappeared chats? Bring them all back:
```bash
wb merge
```
Close WorkBuddy AI, run `wb merge`, and relaunch. **All past conversations from every account will instantly reappear in your sidebar.**

### 3. Switch accounts with zero browser friction:
```bash
wb save personal       # Save currently logged-in account
wb save work           # Save a second account
wb switch personal     # Jump between accounts instantly (chats stay merged!)
```

---

## 🚀 All Commands at a Glance

### Recover / Merge Chat History
```bash
wb merge                     # Reassign all sessions to active account
wb merge --universal         # Make chats visible to ANY account (shared mode)
wb merge --restore-deleted   # Also unhide previously soft-deleted sessions
wb merge --force             # Auto-close WorkBuddy before applying changes
```

### Profile Management
```bash
wb status                    # View active account, token expiration & session stats
wb list                      # List all saved profiles
wb save <name>               # Snapshot current credentials under a custom name
wb switch <name>             # Switch active account and auto-sync history
wb delete <name>             # Remove a saved profile
wb backup                    # Create on-demand backup of database & auth files
```

---

## 🛠️ Cheat Sheet

| Command | Alias | What It Does |
| :--- | :--- | :--- |
| `wb merge` | `wb -m` | Reassign all chat history to active account |
| `wb status` | `wb -s` | View active login state, token expiry & session stats |
| `wb save <name>` | | Save current credentials as a profile |
| `wb switch <name>` | | Switch active profile and auto-sync chats |
| `wb list` | `wb -l` | List all saved profiles |
| `wb backup` | | Create manual snapshot of database & credentials |
| `wb install` | | Symlink `wb` CLI globally |

---

## 🇮🇷 راهنمای سریع (TL;DR فارسی)

### ۱. نصب:
```bash
git clone https://github.com/abolfazl-moeini/workbuddy-toolbox.git
cd workbuddy-toolbox
chmod +x wb-toolbox.sh && ./wb-toolbox.sh install
```

### ۲. برگرداندن فوری تمام چت‌ها در اکانت فعال:
اگر لاگ‌اوت کردید یا اکانت را تغییر دادید و چت‌های قبلی غیب شدند:
```bash
wb merge
```
برنامه را باز کنید؛ تمام تاریخچه‌ها بازگشته‌اند!

### ۳. جابجایی بین چند اکانت بدون باز کردن مرورگر:
```bash
wb save personal      # ذخیره اکانت فعلی با نام دلخواه
wb switch work        # سوئیچ آنی به اکانت دیگر (چت‌ها حفظ و ادغام می‌شوند)
```

### ۴. وضعیت اکانت و توکن:
```bash
wb status             # مشاهده ایمیل فعال، تاریخ انقضای توکن و تعداد سشن‌ها
```

---

## 📄 License

MIT License.
