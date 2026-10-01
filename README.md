# Shell File Transfer

Share files between your machine and any remote shell (Bash or Rails console or anything that can do HTTP requests) via a Cloudflare tunnel.

SSH is usually how shell file transfer is done, but when I get an AWS or Heroku shell using their CLI, idk the SSH creds to do `scp`.

In this case, I find it easier to transfer files via HTTPS. This tool is to make that super easy.

**WARNING: This EVAL stunt is performed by a trained professional**

## Terminologies

* Local host machine: Whichever machine that has this git repo and hosts the server using cloudflared
* Remote shell: The client

## Prerequisites

For your local host machine:
- `python3`
- `cloudflared`

For the remote shell:
- Bash: `curl`
- Ruby console: Nothing, uses standard `net/http`

## How to use

In your local host machine:

```bash
git clone git@github.com:subins2000/shell-file-transfer.git
cd shell-file-transfer
./host.sh
```

Set the given `SFT_HOST` environment variable in the remote shell.

Then, either copy paste the relevant file in `client/` directly into the shell or use the eval option.

## Clients

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
