# 📖 User Guide & Troubleshooting

## ⌨️ Global Shortcuts
| Action | Shortcut |
| :--- | :--- |
| **Speak Selection** | `Cmd + Shift + .` |
| **Play/Pause** | `Cmd + Shift + /` |
| **Stop** | `Cmd + Shift + ,` |
| **Export to Desktop** | `Cmd + Shift + M` |

## 🛠 Troubleshooting

### 1. "Initializing SuperSay..." screen hangs forever
This happens if the backend server fails to start.
- Ensure no other app is using port `10101`.
- Run `pkill -f SuperSayServer` in Terminal and restart.

### 2. "Accessibility Access: false" in logs
If you see this even after granting permission:
1. Quit SuperSay.
2. Run `tccutil reset Accessibility com.himudigonda.SuperSay` in Terminal.
3. Open System Settings > Accessibility.
4. Manually add SuperSay if it's missing.

### 3. Audio clicks or pops
We use a 50ms cross-fade between sentences. If you hear popping, go to `backend/app/services/audio.py` and increase `duration_sec` in `apply_fade` to `0.08`.

### 4. Text selection isn't working in Chrome/Slack
Some apps are slow to respond to copy commands. We use a 250ms delay to wait for the clipboard. If selection still fails, try focusing the window before hitting the shortcut.
