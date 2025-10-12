# alpi

Post-install scripts for **vanilla Arch Linux** that set up my suckless-based desktop (dwm, st, dmenu, slock, slstatus), look & feel, apps, and a few safe optimizations.  
**Made for my own taste and workflow. No guarantees. Use at your own risk.**

> **Disclaimer**  
> These scripts are personal. **No warranties** and **no responsibility** for bugs, data loss, or broken systems.

## Requirements
- Fresh Arch install with `pacman` working
- A network connection
- A normal user with `sudo` privileges
- Interactive TTY if you want to be prompted for Vanilla vs Custom suckless

## Get started (custom suckless)
```bash
git clone <this-repo>
cd alpi
chmod +x *
./alpi.sh --nirucon
```

## Get started (vanilla suckless)
```bash
git clone <this-repo>
cd alpi
chmod +x *
./alpi.sh
```
