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

Create a wrapper, for example in `/usr/bin/kgitlabsh`, that contains:

```sh
#!/bin/bash
exec /path/to/kgitlab exec-shell "$@"
```

Then change the GitLab shell user's shell to `/usr/bin/kgitlabsh` by adding:

```ruby
user['shell'] = "/usr/bin/kgitlabsh"
```

to `/etc/gitlab/gitlab.rb` and running `gitlab-ctl reconfigure`.

Then, when the user logs in with valid Kerberos credentials, and is listed in the GitLab shell user's `.k5login`, and has an associated dummy SSH key as managed by kgitlab, they will be put into the GitLab shell for doing all the pulling and pushing that they would be able to do with their normal SSH key.  The ability to also authenticate with a normal SSH key is preserved.

You may also want to add the following to your system `sshd_config`:

```
Match User git
    PasswordAuthentication no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
```

to match the security precautions taken by GitLab's normal SSH authentication scheme.
