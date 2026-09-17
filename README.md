# WorkBuddy Toolbox (`wb`)

> **TL;DR:** WorkBuddy AI hides your local chat history when you switch accounts or log out (because conversations in SQLite are partitioned by `userId`).  
> **`wb merge`** instantly unhides and brings all your chat sessions into your active account.  
> **`wb switch <name>`** lets you switch between multiple accounts in one command without opening the browser.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-lightgrey.svg)]()
[![Shell](https://img.shields.io/badge/Shell-Bash-black.svg)]()

---

## ⚡ Quick Start

```bash
git clone https://github.com/abolfazl-moeini/workbuddy-toolbox.git
cd workbuddy-toolbox
chmod +x wb-toolbox.sh
./wb-toolbox.sh install
```

This installs `wb` globally in your PATH.

---

## 🚀 Common Commands

### 1. Recover / Merge All Chats
Brings all conversations from previous accounts into the currently active session:
```bash
wb merge
```
*Creates an automatic database backup before applying changes.*

Options:
* `wb merge --universal` : Makes all chats universally visible across any logged-in account.
* `wb merge --restore-deleted` : Also unhides soft-deleted sessions.
* `wb merge --force` : Automatically closes WorkBuddy if it is running.

---

### 2. Multi-Account Switching
Save profiles and switch between them instantly:
```bash
# Save current logged-in account
wb save personal

# Save another account
wb save work

# List saved accounts
wb list

# Switch account (auto-syncs chat history)
wb switch work
```

---

### 3. Check Account & Session Status
```bash
wb status
```

Example Output:
```text
=== WorkBuddy AI Status ===
Application:      ○ Not running
Login State:      Authenticated
Active Email:     user@example.com
User ID (UID):    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
UIN:              100000000000
Token Valid To:   2027-01-01 00:00:00

--- Chat History & Database ---
Database Path:    ~/.workbuddy-ai/workbuddy.db
Total Sessions:   30
Visible to User:  30
Hidden (Other UID): 0
```

---

### 4. Create an On-Demand Backup
```bash
wb backup
```
Snapshots your SQLite database and credentials to `~/.workbuddy-toolbox/backups/`.

---

## 🛠️ Command Cheat Sheet

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

## 🇮🇷 خلاصه به فارسی (TL;DR)

ورک‌بادی بعد از خروج یا تغییر اکانت، تاریخچه چت‌ها را پاک نمی‌کند، بلکه آن‌ها را بر اساس `userId` فیلتر و مخفی می‌کند.

* **`wb merge`**: تمام چت‌های قبلی را به اکانت فعال متصل می‌کند تا همگی در سایدبار ظاهر شوند.
* **`wb switch <name>`**: سوئیچ فوری بین اکانت‌ها بدون نیاز به لاگین در مرورگر.
* **`wb status`**: نمایش اطلاعات اکانت، وضعیت توکن و تعداد چت‌های موجود.

---

## 📄 License

MIT License.
