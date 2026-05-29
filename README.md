<p align="center">

<img width="400" height="400" alt="studio_voly_small (2)" src="https://github.com/user-attachments/assets/cff95849-ff1d-4e9c-a748-092487d31a51" />
</p>

<p align="center">
  A modular Windows optimisation and IT utility suite built with PowerShell and WPF.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows-blue">
  <img src="https://img.shields.io/badge/Language-PowerShell-5391FE">
  <img src="https://img.shields.io/badge/UI-WPF-6A5ACD">
  <img src="https://img.shields.io/badge/Status-Active%20Development-orange">
</p>

---

# ⚠️ Project Status

The toolkit is currently undergoing a major rebuild phase.

Versions 1 and 2 were successfully completed, however the original experimental V3 became too large and unstable to maintain safely. The project has now been rolled back to the stable V2.7 foundation while the new V3 architecture and UI are rebuilt properly.

Current focus areas include:

- UI rebuild
- Ticket system improvements
- Action execution stability
- Startup optimisation
- Modular restructuring
- ~~Studio Voly branding integration~~

The toolkit should currently be treated as experimental during this rebuild phase.

---

# ✨ Features

## 🧹 Cleanup Utilities

- Temp cleanup
- Recycle Bin cleanup
- Windows Update cache cleanup
- Delivery Optimisation cache cleanup
- Thumbnail cache cleanup

---

## ⚡ Windows Tweaks

- Disable Bing Search
- Disable Widgets
- Disable Suggested Apps
- Disable Meet Now
- Restore Classic Context Menu
- Disable Online Tips
- Disable Advertising ID

---

## 📦 Applications Module

- Common app installs
- Installed app scanning
- Bulk uninstall support
- Technician deployment workflows

---

## 🌐 Network Utilities

- Network reset tools
- IPv6 controls
- Advanced repair scripts
- Network troubleshooting utilities

---

## 🎫 Ticketing System

Current functionality includes:

- Local ticket storage
- Ticket statuses
- Reply drafting
- Backup support
- Filtering system
- Deleted ticket recovery behaviour

Planned improvements:

- Background pending replies
- Persistent reply queue
- Better Outlook integration
- Multi status filtering
- Right click status updates

---

# 🎨 UI Rebuild

The toolkit UI is currently being rebuilt from the ground up.

### Current Goals

- Faster startup
- Remove white screen loading
- Better modular architecture
- Custom title bar
- Studio Voly branding
- Improved responsiveness
- Cleaner layouts

---

# ▶️ Action System

The toolkit uses a centralised action execution system.

The long term goal is:

1. Select actions across tabs
2. Press Play
3. Execute tasks sequentially
4. Display live logging
5. Show execution progress

Current development is heavily focused on stabilising this workflow.

---

# 🪵 Logging System

The toolkit contains detailed logging for:

- UI startup
- Module loading
- Script execution
- Ticket workflows
- Action execution
- Error diagnostics

---

# 📁 Project Structure

```text
src\
 ├── Apps\
 ├── Core\
 ├── Intro\
 ├── Tickets\
 ├── UI\
 └── Scripts\
      ├── Cleanup\
      ├── Network\
      └── Tweaks\
```

---

# 🚀 Running the Toolkit

## Bootstrap Launcher

```powershell
irm 'https://raw.githubusercontent.com/VoIyboo/Windows-Optimiser-Toolkit-/main/bootstrap.ps1' | iex
```

---

# 🛠️ Development Philosophy

The toolkit is built around:

- Modular design
- Technician workflows
- Real world IT usage
- Stability first development
- Expandability
- Clean UI experiences

The rebuild phase exists because long term maintainability matters more than feature bloat.

---

# 🧠 Long Term Vision

The long term goal is to evolve the toolkit into:

- A professional Windows optimisation suite
- A technician support companion
- A deployable IT support platform
- A centralised maintenance environment

Future ideas may include:

- Remote support features
- Health dashboards
- Plugin systems
- Cloud sync
- AI assisted diagnostics
- Multi machine management

---

# 🏷️ Branding

The toolkit is now part of the Studio Voly ecosystem.

Current branding direction:

- Dark modern UI
- Blue accent styling
- Minimal clutter
- Technician focused layouts

---

# ⚠️ Disclaimer

This toolkit performs system level changes and administrative actions.

Always review scripts before use and test changes in controlled environments where possible.

---

# ❤️ Final Notes

The Quinn Optimiser Toolkit started as a simple cleanup script and slowly evolved into a much larger project through real world IT work, experimentation and rebuilding lessons learned the hard way.

The rebuild exists because the goal is no longer to simply add features.

The goal is to build it properly.
