local failures = 0
local alerts = {}
local asyncRequest = nil
local server = nil

local function check(name, condition)
    if condition then
        print("ok - " .. name)
    else
        failures = failures + 1
        print("not ok - " .. name)
    end
end

local function newServer(ssl, bonjour)
    local instance = {
        ssl = ssl,
        bonjour = bonjour,
        stopped = false,
    }

    function instance:setInterface(value)
        self.interface = value
        return self
    end

    function instance:setPort(value)
        self.port = value
        return self
    end

    function instance:maxBodySize(value)
        self.bodySize = value
        return self
    end

    function instance:setCallback(value)
        self.callback = value
        return self
    end

    function instance:start()
        self.started = true
        return self
    end

    function instance:stop()
        self.stopped = true
    end

    server = instance
    return instance
end

hs = {
    alert = {
        show = function(message)
            table.insert(alerts, message)
        end,
    },
    httpserver = { new = newServer },
    http = {
        asyncPost = function(url, body, headers, callback)
            asyncRequest = { url = url, body = body, headers = headers, callback = callback }
        end,
    },
    json = {
        encode = function()
            return "{}"
        end,
        decode = function()
            return nil
        end,
    },
    hotkey = {
        bind = function()
            error("hotkey should be disabled in this test")
        end,
    },
    pasteboard = { getContents = function() return nil end },
    printf = function() end,
}

local Integration = dofile("src/send_to_hammerspoon.lua")
local started = Integration.start({
    serviceConfigFile = "tests/fixtures/service.fixture",
    openRouterKeyFile = "tests/fixtures/api-key.fixture",
    hotkey = { enabled = false },
})

check("starts with test configuration", started == true)
check("disables TLS only for loopback transport", server.ssl == false)
check("disables Bonjour advertisement", server.bonjour == false)
check("binds only to localhost", server.interface == "localhost")
check("loads local service port", server.port == 18492)
check("enforces body limit", server.bodySize == 50000)

local _, wrongPathStatus = server.callback("POST", "/wrong", {}, "Example")
check("rejects unknown endpoint", wrongPathStatus == 404)

local _, unauthorizedStatus = server.callback("POST", "/event", {}, "Example")
check("rejects missing token", unauthorizedStatus == 401)

local headers = {
    ["x-send-to-hammerspoon-token"] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
}
local _, emptyStatus = server.callback("POST", "/event", headers, "  ")
check("rejects empty text", emptyStatus == 409)

local _, acceptedStatus = server.callback("POST", "/event", headers, "Meet Thursday at 10")
check("accepts authenticated text", acceptedStatus == 202)
check("sends only to OpenRouter HTTPS endpoint", asyncRequest.url == "https://openrouter.ai/api/v1/chat/completions")

local _, busyStatus = server.callback("POST", "/event", headers, "Second request")
check("rejects concurrent extraction", busyStatus == 409)

asyncRequest.callback(500, "bad response")
local _, acceptedAfterCallback = server.callback("POST", "/event", headers, "Try again")
check("clears busy state after response", acceptedAfterCallback == 202)

Integration.stop()
check("stops local receiver", server.stopped == true)

local missingKeyStarted = Integration.start({
    serviceConfigFile = "tests/fixtures/service.fixture",
    openRouterKeyFile = "tests/fixtures/does-not-exist.fixture",
    hotkey = { enabled = false },
})
local _, missingKeyStatus = server.callback("POST", "/event", headers, "Example")
check("can start before key is configured", missingKeyStarted == true)
check("reports missing key to Service", missingKeyStatus == 409)

Integration.stop()
os.exit(failures == 0 and 0 or 1)
