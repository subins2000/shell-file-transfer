# SFT Ruby client — requires ENV["SFT_HOST"]
# Load:
#   require "net/http"; require "uri"
#   eval Net::HTTP.get(URI("#{ENV['SFT_HOST']}/clients/ruby.rb"))

require "net/http"
require "uri"

raise "SFT_HOST is not set" if ENV["SFT_HOST"].to_s.strip.empty?

def sft_send(path)
  path = path.to_s
  raise "usage: sft_send <path>" if path.empty?
  raise "sft_send: file not found: #{path}" unless File.file?(path)

  name = File.basename(path)
  uri = URI("#{ENV['SFT_HOST']}/send?name=#{URI.encode_www_form_component(name)}")
  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "application/octet-stream"
  req.body = File.binread(path)

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
    File.binwrite(name, res.body)
  end
  puts "received #{name}"
  name
end
