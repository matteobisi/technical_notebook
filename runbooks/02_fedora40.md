# Fedora40 what do fo after setup  

## Description
I've just switched my personal laptop to **Fedora40** with Gnome 46.
Some notes about some tweaks I made after the setup to live happy

## DNF config
I've added a couple of things about DNF config ( /etc/dnf/dnf.conf )

```
max_parallel_downloads=10
defaultyes=True
```
- max_parallel_download, increment the number of parallel download while upgrade  
- defaultyes=True, is self explainetory  

## Gnome expansions
Gnome 46 is good but not perfect for my preferences. I just wanted to tweak it a little bit
- Dash to Dock: this gives you back the dash, I putted it on the left  
- No overview at start-up: it quit the start in overview
- Weather or Not: just to have my weather on upper panel
- Tray Icons: Reloaded: this give me back the tray icon on the panel  

## Icons theme
I really really hate the default icons of Fedora/Gnome, so after some test i choosed [Nordzy-icon](https://github.com/alvatip/Nordzy-icon). Follow the instruction on they repo for the installation part, to enable it Tweak-->Appearance after a logoff logon process.  

