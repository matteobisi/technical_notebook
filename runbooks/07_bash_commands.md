# Bash Commands Cheatsheet

A list of common bash commands with a brief description and example.

## Table of Contents

*   [File and Directory Management](#file-and-directory-management)
*   [Text Processing](#text-processing)
*   [Permissions](#permissions)
*   [Network](#network)
*   [Other](#other)

---

## File and Directory Management

| Command | Description | Example |
| :--- | :--- | :--- |
| `ls` | List directory contents | `ls -l` |
| `cd` | Change the current directory | `cd /home/user` |
| `pwd` | Print the name of the current working directory | `pwd` |
| `cat` | Concatenate and display files | `cat file.txt` |
| `echo` | Display a line of text | `echo "Hello, world!"` |
| `touch` | Change file timestamps or create an empty file | `touch new_file.txt` |
| `mkdir` | Create a new directory | `mkdir new_directory` |
| `rm` | Remove files or directories | `rm file.txt` |
| `cp` | Copy files and directories | `cp source.txt destination.txt` |
| `mv` | Move or rename files and directories | `mv old_name.txt new_name.txt` |
| `find` | Search for files in a directory hierarchy | `find . -name "*.txt"` |

## Text Processing

| Command | Description | Example |
| :--- | :--- | :--- |
| `grep` | Print lines that match patterns | `grep "pattern" file.txt` |
| `awk` | Pattern scanning and processing language | `awk '{print $1}' file.txt` |
| `sed` | Stream editor for filtering and transforming text | `sed 's/old/new/g' file.txt` |
| `head` | Output the first part of files | `head -n 10 file.txt` |
| `tail` | Output the last part of files | `tail -n 10 file.txt` |

## Permissions

| Command | Description | Example |
| :--- | :--- | :--- |
| `chmod` | Change file mode bits | `chmod 755 file.sh` |
| `chown` | Change file owner and group | `chown user:group file.txt` |

## Network

| Command | Description | Example |
| :--- | :--- | :--- |
| `curl` | Transfer data from or to a server | `curl -O https://example.com/file.zip` |

## Other

| Command | Description | Example |
| :--- | :--- | :--- |
| `alias` | Define or display aliases | `alias ll='ls -l'` |
