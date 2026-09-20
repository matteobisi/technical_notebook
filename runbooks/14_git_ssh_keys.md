# SSH Keys for GitHub and GitLab

This guide configures a passphrase-protected Ed25519 SSH key for Git operations on modern Linux and macOS. It covers key creation, local SSH and Git configuration, adding the public key to GitHub or GitLab, and verifying the connection.

## Table of Contents

- [Security baseline](#security-baseline)
- [Create the key pair](#create-the-key-pair)
- [Configure the SSH client and agent](#configure-the-ssh-client-and-agent)
- [Add the public key to GitHub](#add-the-public-key-to-github)
- [Add the public key to GitLab](#add-the-public-key-to-gitlab)
- [Use SSH with Git](#use-ssh-with-git)
- [Verify the connection](#verify-the-connection)
- [Manage and rotate keys](#manage-and-rotate-keys)
- [Hardware security keys](#hardware-security-keys)

---

## Security Baseline

- Use an **Ed25519** key. GitLab identifies it as the preferred key type; GitHub documents Ed25519 as its standard choice. Use RSA only for a legacy system that cannot use Ed25519, and use at least 4096 bits.
- Protect the private key with a strong, unique passphrase. Do not upload, email, chat, or store the private key in an unencrypted cloud-sync service.
- Create a different key for each device. This limits the effect of a lost or compromised device.
- Upload only the public key, whose filename ends in `.pub`. The private key has no `.pub` suffix.
- Before accepting a new server host key, compare its fingerprint with the provider's published fingerprint.

## Create the Key Pair

First check the OpenSSH version and existing key files:

```shell
ssh -V
ls -al ~/.ssh
```

Generate a dedicated key with a descriptive comment. Replace the email address and use a unique filename when prompted, such as `~/.ssh/id_ed25519_github_gitlab`.

```shell
ssh-keygen -t ed25519 -C "you@example.com"
```

At the passphrase prompts, enter a strong passphrase rather than leaving it empty. OpenSSH stores the public key beside the private key with `.pub` appended. Keep the private key readable only by its owner:

```shell
chmod 600 ~/.ssh/id_ed25519_github_gitlab
```

If Ed25519 is unavailable on a legacy system, generate a 4096-bit RSA key instead:

```shell
ssh-keygen -t rsa -b 4096 -C "you@example.com"
```

## Configure the SSH Client and Agent

Set restrictive permissions on the SSH directory and configuration file:

```shell
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/config
chmod 600 ~/.ssh/config
```

Add the key to `~/.ssh/config`. Replace the `IdentityFile` value with the private-key path selected during key creation. `IdentitiesOnly yes` makes SSH offer this identity rather than trying every key held by the agent.

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github_gitlab
  IdentitiesOnly yes
  AddKeysToAgent yes

Host gitlab.com
  HostName gitlab.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github_gitlab
  IdentitiesOnly yes
  AddKeysToAgent yes
```

Start an agent in the current shell and load the private key:

```shell
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_github_gitlab
```

On macOS, add the following setting to each relevant `Host` block to save the passphrase in the Apple Keychain, then load the key with the macOS-specific command:

```text
  UseKeychain yes
```

```shell
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_github_gitlab
```

## Add the Public Key to GitHub

Copy or display the **public** key:

```shell
# macOS
pbcopy < ~/.ssh/id_ed25519_github_gitlab.pub

# Linux: display it, then copy the complete line
cat ~/.ssh/id_ed25519_github_gitlab.pub
```

In GitHub, open the profile menu in the upper-right corner, then select **Settings** > **SSH and GPG keys** > **New SSH key** (or **Add SSH key**). Enter a descriptive title, select **Authentication Key**, paste the public-key line, and select **Add SSH key**.

Alternatively, after authenticating GitHub CLI, add the public key with:

```shell
gh ssh-key add ~/.ssh/id_ed25519_github_gitlab.pub --type authentication --title "My Linux or macOS device"
```

## Add the Public Key to GitLab

Copy or display the same public key:

```shell
# macOS
tr -d '\n' < ~/.ssh/id_ed25519_github_gitlab.pub | pbcopy

# Linux: display it, then copy the complete line
cat ~/.ssh/id_ed25519_github_gitlab.pub
```

In GitLab, open the avatar menu in the upper-right corner, then select **Edit profile** > **Access** > **SSH keys** > **Add new key**. Paste the public key, give it a descriptive title, select the appropriate usage type, optionally set an expiration date, and select **Add key**.

For GitLab Self-Managed or Dedicated, use the equivalent profile settings on that instance.

## Use SSH with Git

When cloning a repository, use the **Code** button in GitHub or GitLab and copy the SSH URL.

```shell
# GitHub
git clone git@github.com:OWNER/REPOSITORY.git

# GitLab
git clone git@gitlab.com:NAMESPACE/PROJECT.git
```

To convert an existing checkout from HTTPS to SSH:

```shell
git remote -v

# GitHub
git remote set-url origin git@github.com:OWNER/REPOSITORY.git

# GitLab
git remote set-url origin git@gitlab.com:NAMESPACE/PROJECT.git

git remote -v
```

The SSH client configuration above is the preferred local setup because Git uses SSH to contact SSH remotes. If a repository must use a different private key, configure that repository only:

```shell
git config core.sshCommand "ssh -o IdentitiesOnly=yes -i ~/.ssh/private-key-filename-for-this-repository -F /dev/null"
```

This setting bypasses the SSH agent for that repository. Do not use `--global` unless every repository should use the same key.

## Verify the Connection

On the first connection, do **not** accept the server host key until its displayed fingerprint matches the provider's published fingerprint.

For GitHub:

```shell
ssh -T git@github.com
```

The Ed25519 host fingerprint published by GitHub is:

```text
SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU
```

Successful authentication includes your GitHub username; the command intentionally exits with status `1` because GitHub does not provide shell access.

For GitLab.com:

```shell
ssh -T git@gitlab.com
```

Confirm the host key against GitLab.com's published SSH host-key fingerprints. Successful authentication displays a welcome message. For a self-managed GitLab instance, use its hostname in the command and verify against `https://gitlab.example.com/help/instance_configuration#ssh-host-keys-fingerprints`.

After verification, test Git access from a repository:

```shell
git fetch
git push
```

## Manage and Rotate Keys

List the fingerprint of the local public key:

```shell
ssh-keygen -l -f ~/.ssh/id_ed25519_github_gitlab.pub
```

Remove a key from GitHub or GitLab immediately if the device or private key may be compromised. Generate and register a replacement key instead of sharing a private key with another device. GitLab supports an expiration date for account SSH keys, which can limit the lifetime of a credential.

To change the passphrase of an existing private key:

```shell
ssh-keygen -p -f ~/.ssh/id_ed25519_github_gitlab
```

## Hardware Security Keys

For stronger protection of private-key material, use a FIDO2 hardware security key with OpenSSH 8.2 or later. With the device attached, create an `ed25519-sk` key:

```shell
ssh-keygen -t ed25519-sk -C "you@example.com"
```

The security key must be present when authenticating. Register the generated public key with GitHub or GitLab using the same account settings described above.

## Sources

- https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
- https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account
- https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection
- https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
- https://docs.github.com/en/get-started/git-basics/managing-remote-repositories
- https://docs.gitlab.com/user/ssh/
- https://docs.gitlab.com/user/ssh_advanced/
- https://docs.gitlab.com/topics/git/clone/
- https://man.openbsd.org/ssh-keygen
- https://man.openbsd.org/ssh_config
