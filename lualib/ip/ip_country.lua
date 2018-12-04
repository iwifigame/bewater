local skynet    = require "skynet"
local service   = require "skynet.service"

local addr
skynet.init(function()
    addr = service.new("ip_country", function()
        local skynet = require "skynet"
        local util  = require "util"
        local http  = require "web.http_helper"
        local mongo = require "db.mongo_helper"

        local CMD = {}
        local ips = {}
        local function load_all()
            -- todo 改用指针
            --[[local cur = mongo.find("ipinfo", {}, {_id = false})
            while cur:hasNext() do
                local ret = cur:next()
                ips[ret.ip] = ret.country
            end
            ]]
            local data = mongo.find("ipinfo", {}, {_id = false})
            for _, v in pairs(data) do
                ips[v.ip] = v.country
            end
        end

        function CMD.get_country(ip)
            assert(ip)
            if ips[ip] then
                return ips[ip]
            else
                ips[ip] = "unknown"
            end
            skynet.fork(function()
                local user_agent = 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2272.118 Safari/537.36'
                local referer = 'http://www.ip.cn/index.php?ip=http%3A%2F%2F203.179.55.190'
                local headers = { 
                    ['User-Agent'] = user_agent, 
                    ['Referer'] = referer
                }   
                local url = string.format('http://www.ip.cn/index.php?ip=%s', ip) 
                local ret, resp = http.get(url, nil, headers)
                if not ret then
                    skynet.error(string.format("request www.ip.cn error ip:%s", ip))
                end
                local str = string.match(resp, "GeoIP:(.+)</p><p>")
                str = string.match(str or "", " ([^,]+)$")
                if not str then
                    skynet.error("request ip country error, resp:", resp)
                end
                ips[ip] = str or "unknown"
                mongo.insert("ipinfo", {ip = ip, country = str})
            end)
            return "unknown"
        end

        skynet.start(function()
            load_all()
            skynet.dispatch("lua", function(_, _, cmd, ...)
                local f = assert(CMD[cmd], cmd)
                util.ret(f(...))
            end)
        end)
    end)
end)

local M = {}
function M.is_china(ip)
    local country = M.get_country(ip)
    return country == "China" or country == "unknown"
end
function M.get_country(ip)
    return skynet.call(addr, "lua", "get_country", ip)
end
return M