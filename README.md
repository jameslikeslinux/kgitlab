# kgitlab

kgitlab is a GitLab system hook listener to automatically manage the git user's `.k5login` file when GitLab users are created or destroyed.  Because the GitLab shell expects SSH users to authenticate with SSH keys, kgitlab generates a sort of "dummy" SSH key for users and maps it to a Kerberos principal.  Then, on login, kgitlab can lookup the key associated with the Kerberos principal and pass the right key number to GitLab shell to authenticate the user.

## Installation

Clone the repository and run:

    $ rake install

## Usage

kgitlab provides a command-line interface.  It has two modes, a server and a shell executor.

### Server

To run the server, first define a configuration file like:

```yaml
---
# The port to start a web server on to listen for system hook events
port: 8000

# The API endpoint for your GitLab installation
api_url: 'https://gitlab.example.com/api/v3'

# The API token for a user with admin rights
api_token: 'a-long-random-string'

# GitLab's shell user, usually 'git'
git_user: 'git'

# The Kerberos realm to append to GitLab usernames for Kerberos
# authentication
realm: 'EXAMPLE.COM'
```

Then run the server like:

    # kgitlab server --config /path/to/config.yaml

You may need to ensure that the GitLab shell user's `.k5login` file has the right SELinux context: `system_u:object_r:krb5_home_t:s0`.  That is beyond the scope of this program.

### Shell Executor

Set the SSH configuration for the git user to the following to ensure they cannot escape the GitLab shell:

```
Match User git
    PasswordAuthentication no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
    ForceCommand /path/to/kgitlab exec-shell
```

Then, if the user logs in with valid Kerberos credentials, and is listed in the GitLab shell user's `.k5login`, and has an associated dummy SSH key as managed by kgitlab, then they will be put into the GitLab shell for doing all the pulling and pushing that they would be able to do with their normal SSH key.  Otherwise the program exits and the user is logged out.
