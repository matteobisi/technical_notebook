# Ubuntu srv Vs sshd config

Ubuntu 24.04 give you the possibility. to select  public key while configuring to enable remote ssh key. It could fetch public key from files or github .

If you configure some keys, by default it will create a new file

`/etc/ssh/sshd_config.d/50-cloud-init.conf` to block the ssh password login and permit only the key login.
This file is authomatically loaded in the configuration.

```bash
q!PasswordAuthentication no
```

To permit the login with password it’s only necessary to delete that file and restart the sshd daemon

```bash
sudo systemctl restart ssh


```

PasswordAuthentication as default is yes.

## Advanced config

It’s also possible to set the password login enabled for some users but not for others.

It could be done inside the **`/etc/ssh/sshd_config`**

adding the following lines to the end

```bash
# Global config (outside any Match blocks)
PasswordAuthentication yes
PubkeyAuthentication yes


# Per-user overrides
Match User sighup
    PasswordAuthentication no
    PubkeyAuthentication yes


Match User soc
    PasswordAuthentication yes
    PubkeyAuthentication yes


```

Here’s an enhanced and technically polished version of your text, with grammar corrected and technical details clarified:

***

# Ubuntu SSHD Configuration: Public Key vs Password Authentication

Ubuntu 24.04 allows you to configure SSH authentication using public keys during setup. Keys can be imported either from local files or external sources such as GitHub.

When you configure SSH keys, Ubuntu automatically creates the following configuration file:

`/etc/ssh/sshd_config.d/50-cloud-init.conf`

This file disables password authentication and enables key-based login. Since all files inside `/etc/ssh/sshd_config.d/` are loaded by `sshd`, the setting applies automatically.

Example content:

```bash
PasswordAuthentication no
```

If you want to re-enable password login, you can simply remove the file and restart the SSH daemon:

```bash
sudo systemctl restart sshd
```

By default, `PasswordAuthentication` is set to `yes` if not overridden.

***

## Advanced Configuration

It is also possible to enable password login for specific users while enforcing key-only login for others. This is done in the main SSH configuration file:

`/etc/ssh/sshd_config`

At the end of the file, add rules like the following:

```bash
# Global defaults
PasswordAuthentication yes
PubkeyAuthentication yes

# Per-user overrides
Match User sighup
    PasswordAuthentication no
    PubkeyAuthentication yes

Match User soc
    PasswordAuthentication yes
    PubkeyAuthentication yes
```

In this example:

- User `sighup` can log in **only with SSH keys**.
- User `soc` can log in using **either password or SSH keys**.
- All other users follow the global defaults defined above.

***