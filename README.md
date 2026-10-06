# Shell File Transfer

Share files between your machine and any remote shell (Bash or Rails console or anything that can do HTTP requests) via a public HTTPS tunnel.

SSH is usually how shell file transfer is done, but when I get an AWS or Heroku shell using their CLI, idk the SSH creds to do `scp`.

In this case, I find it easier to transfer files via HTTPS. This tool is to make that super easy.

**WARNING: This EVAL stunt is performed by a trained professional**

## Features

* Simple client scripts
* Optional encryption so that the tunnel can't read payload
* Uses a free public tunnel (Cloudflare by default, or localhost.run)

## Terminologies

* Local host machine: Whichever machine that has this git repo and hosts the server + tunnel
* Remote shell: The client

## Requirements

For your local host machine:
- `python3`
- `cloudflared` (if using `--tunnel-service cloudflare`, default)
- `ssh` (if using `--tunnel-service localhostrun`)
- `openssl` (only if using `--encrypt`)

For the remote shell:
- Bash: `curl` (and `openssl` + `python3` for encrypted client)
- Ruby console: stdlib only (`openssl` gem is part of MRI stdlib)

## How to use

In your local host machine:

```bash
git clone git@github.com:subins2000/shell-file-transfer.git
cd shell-file-transfer

# Use without wire encryption
./host.sh

# encrypt file bodies on the wire so the tunnel provider cannot read payloads:
./host.sh --encrypt

# use localhost.run instead of Cloudflare quick tunnels:
./host.sh --tunnel-service localhostrun
./host.sh --encrypt --tunnel-service localhostrun
```

Set the given `SFT_HOST` environment variable in the remote shell. With `--encrypt`, also set `SFT_KEY`.

Then, either copy paste the relevant file in `clients/` directly into the remote shell or use the eval option.

## In the remote client shell

### Bash

```bash
# Initial one-time run
export SFT_HOST='https://….trycloudflare.com'
eval "$(curl -fsSL "$SFT_HOST/clients/bash.sh")"
# ^ Or instead of eval, copy paste from clients/bash.sh

# Usage
sft_send path.txt
sft_receive filename.txt
```

### Ruby / Rails console

```ruby
# Initial one-time run
ENV["SFT_HOST"] = "https://….trycloudflare.com"
require "net/http"; require "uri"
eval Net::HTTP.get(URI("#{ENV['SFT_HOST']}/clients/ruby.rb"))
# ^ Or instead of eval, copy paste from clients/ruby.rb

# Usage
sft_send "path.txt"
sft_receive "filename.txt"
```

Place files to send to remote in the host's `storage/` folder. Then, use `sft_receive 'filename.txt'` in the remote shell.

Files sent using `sft_send 'path.txt'` from remote is also stored in the host's `storage/` folder.

Wire encryption uses AES-256-CBC via `openssl enc -pbkdf2`. Payload is encrypted in transit, so the tunnel is never able to read it.
