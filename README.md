# Remote Shell File Transfer

Share files between your machine and any remote shell (Bash or Rails console or anything that can do HTTP requests) via a Cloudflare tunnel.

## Prerequisites

For your machine:
- `python3`
- `cloudflared`

For the remote shellL
- Bash: `curl`
- Ruby console: Nothing, uses standard `net/http`

## How to use

In your local machine:

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
# Initial one-time setup
export SFT_HOST='https://….trycloudflare.com'
eval "$(curl -fsSL "$SFT_HOST/clients/bash.sh")"

# Usage
sft_send path.txt
sft_receive filename.txt
```

### Ruby / Rails console

```ruby
# Initial one-time setup
ENV["SFT_HOST"] = "https://….trycloudflare.com"
require "net/http"; require "uri"
eval Net::HTTP.get(URI("#{ENV['SFT_HOST']}/clients/ruby.rb"))

# Usage
sft_send "path.txt"
sft_receive "filename.txt"
```

Place files to send to remote in the host's `storage/` folder. Then, use `sft_receive 'filename.txt'` in the remote shell.

Files sent using `sft_send 'path.txt'` from remote is also stored in the host's `storage/` folder.
