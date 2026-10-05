# SFT Ruby client (encrypted wire) — requires ENV["SFT_HOST"] and ENV["SFT_KEY"]
# Load:
#   require "net/http"; require "uri"; require "openssl"
#   eval Net::HTTP.get(URI("#{ENV['SFT_HOST']}/clients/ruby_enc.rb"))

require "net/http"
require "openssl"
require "uri"

raise "SFT_HOST is not set" if ENV["SFT_HOST"].to_s.strip.empty?
raise "SFT_KEY is not set" if ENV["SFT_KEY"].to_s.strip.empty?

SFT_OPENSSL_ITER = 100_000
SFT_OPENSSL_MAGIC = "Salted__".b

def sft_derive_key_iv(salt)
  # Matches: openssl enc -aes-256-cbc -pbkdf2 -iter 100000
  OpenSSL::PKCS5.pbkdf2_hmac(ENV["SFT_KEY"], salt, SFT_OPENSSL_ITER, 48, "sha256")
end

def sft_encrypt(data)
  salt = OpenSSL::Random.random_bytes(8)
  key_iv = sft_derive_key_iv(salt)
  cipher = OpenSSL::Cipher.new("aes-256-cbc")
  cipher.encrypt
  cipher.key = key_iv[0, 32]
  cipher.iv = key_iv[32, 16]
  SFT_OPENSSL_MAGIC + salt + cipher.update(data) + cipher.final
end

def sft_decrypt(data)
  data = data.b
  raise "openssl decrypt failed: bad header" unless data.bytesize >= 16 && data[0, 8] == SFT_OPENSSL_MAGIC

  salt = data[8, 8]
  ciphertext = data[16..-1]
  key_iv = sft_derive_key_iv(salt)
  cipher = OpenSSL::Cipher.new("aes-256-cbc")
  cipher.decrypt
  cipher.key = key_iv[0, 32]
  cipher.iv = key_iv[32, 16]
  cipher.update(ciphertext) + cipher.final
rescue OpenSSL::Cipher::CipherError => e
  raise "openssl decrypt failed: #{e.message}"
end

def sft_send(path)
  path = path.to_s
  raise "usage: sft_send <path>" if path.empty?
  raise "sft_send: file not found: #{path}" unless File.file?(path)

  name = File.basename(path)
  uri = URI("#{ENV['SFT_HOST']}/send?name=#{URI.encode_www_form_component(name)}")
  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "application/octet-stream"
  req.body = sft_encrypt(File.binread(path))

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
    res = http.request(req)
    raise "sft_send failed: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
  end
  puts "sent #{name}"
  name
end

def sft_receive(name)
  name = File.basename(name.to_s)
  raise "usage: sft_receive <name>" if name.empty?

  uri = URI("#{ENV['SFT_HOST']}/files/#{URI.encode_www_form_component(name)}")
  Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
    res = http.request(Net::HTTP::Get.new(uri))
    raise "sft_receive failed: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    File.binwrite(name, sft_decrypt(res.body))
  end
  puts "received #{name}"
  name
end
