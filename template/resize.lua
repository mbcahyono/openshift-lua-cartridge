--- require magick and resty.http
local magick = require "magick"
local http = require "resty.http"

--- initial settings
local user_agent = 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.86 Safari/537.36'
local content_type = ''
local img_format = ''
local img = ''

--- url
local http_method = ngx.req.get_method()
local url_arg = ngx.unescape_uri(ngx.var.arg_url)

---
if not url_arg or url_arg == '' then
  ngx.say("Do what?")
  return
end

---
local url_mentah = ngx.decode_base64(url_arg)

if not url_mentah then
  ngx.say("Meh")
  return
end

local aes_file = require 'resty.aes'
if not aes_file then
  ngx.say("Module not loaded")
  return
end

local aes = assert(aes_file:new("H\xCC\xD7\x05R\xA0\xD5Z~\xD9\x1E\xFFz\bs\x13", nil, aes_file.cipher(128, 'cbc'),
              {iv="}A\xF3\x05p\xE2\xF2j\x04\xAB\xFF\xD3\t6\xD2\xC6"}))

local enc = aes:decrypt(url_mentah)

if not enc then
  ngx.say("Bad hash")
  return
end

local url = string.gsub(enc, '?$', '')

local httpc = http.new()
httpc:set_timeout(3000)

--- fetch image from remote url
local res, err = httpc:request_uri(url, {
  method = http_method,
  headers = {
    ['User-Agent'] = user_agent,
  }
})

if not res then
  ngx.say("failed to request: ", err)
  return
end

--- if HTTP 301/302, refetch from Location header
if res.status == 301 or res.status == 302 then
  url = res.headers["Location"]
  res, err = httpc:request_uri(url, {
     method = http_method
  })
  if not res then
    ngx.say("failed to request: ", err)
    return
  end
end

--- if HTTP 4xx or 5xx, return default image
if res.status >= 400 and res.status < 600 then
  content_type = 'image/jpeg'
  img_format = 'jpg'
  img = assert(magick.load_image(os.getenv('OPENSHIFT_REPO_DIR') .. 'default.jpg'))
elseif res.status == 200 then
  if http_method == "HEAD" then
    ngx.exit(ngx.HTTP_OK)
  else
    content_type = res.headers['Content-Type']
    img_format = string.gsub(content_type, 'image/', '')
    img = assert(magick.load_image_from_blob(res.body))
  end
end

httpc:close()

img:adaptive_resize(200, 200)
img:set_format('jpg')
img:strip()
img:set_quality(90)
img:write(os.getenv('OPENSHIFT_DATA_DIR') .. 'cache/'.. ngx.var.arg_url)

ngx.exec(ngx.var.request_uri)

